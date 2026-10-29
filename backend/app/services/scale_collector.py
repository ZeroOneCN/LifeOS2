"""体重秤蓝牙采集服务（进程内运行，直接写库）。

随 FastAPI 生命周期启动，复用蚂蚁阿福体重秤读取器（协议来自 XiaomiWatchBlue/weight）。
称重稳定后按「用户 + 当天日期」写入 health_body：

- 每天只保留 1 行，同一天多次称重以最后一次为准覆盖旧值；
- 有阻抗数据时同步写入 BIA 体成分估算结果；
- 每次自动记录同时写入活动日志，便于在「活动日志」页追溯；
- 未安装 bleak / 无蓝牙适配器时自动降级，不影响后端其他功能。
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import date, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.models import ActivityLog, HealthBody, UserProfile
from app.services.scale import ScaleReader

try:  # 无蓝牙依赖时安全降级
    from bleak import BleakScanner

    BLEAK_AVAILABLE = True
except Exception:  # noqa: BLE001 - 任何导入失败都视为不可用
    BleakScanner = None  # type: ignore[assignment]
    BLEAK_AVAILABLE = False

logger = logging.getLogger(__name__)

# 体重稳定后等待阻抗包的时长（秒）：无阻抗时按体重单独落库，有阻抗则合并为一次写入
STABLE_WAIT_SECONDS = 3.0
# 合理体重区间（kg），超出视为误读
MIN_WEIGHT_KG = 0.5
MAX_WEIGHT_KG = 250.0
# 体成分字段映射：体成分算法输出键 -> health_body 列名
BODY_FIELD_MAP = {
    "bmi": "bmi",
    "body_fat": "body_fat_percent",
    "fat_mass": "fat_mass_kg",
    "visceral_fat": "visceral_fat",
    "sub_fat_pct": "subcutaneous_fat_percent",
    "sub_fat_mass": "subcutaneous_fat_kg",
    "water": "water_percent",
    "water_mass": "water_kg",
    "protein_rate": "protein_percent",
    "protein_mass": "protein_kg",
    "bone_rate": "bone_percent",
    "bone": "bone_kg",
    "muscle_rate": "muscle_percent",
    "muscle": "muscle_kg",
    "skeletal_muscle_rate": "skeletal_muscle_percent",
    "skeletal_muscle": "skeletal_muscle_kg",
}


def _calc_age(birthday: date, today: date) -> int:
    """按生日计算周岁年龄。

    Args:
        birthday: 出生日期。
        today: 当前日期。

    Returns:
        周岁年龄（不会是负数）。
    """
    age = today.year - birthday.year - (
        (today.month, today.day) < (birthday.month, birthday.day)
    )
    return max(0, age)


class ScaleWeightCollector:
    """进程内体重秤采集器：BLE 扫描 → 稳定称重 → 覆盖写入当天体重记录 + 活动日志。"""

    def __init__(self) -> None:
        """按配置初始化采集器（不启动扫描）。"""
        self._reader = ScaleReader(
            on_event=self._on_event,
            name_prefix=settings.SCALE_NAME_PREFIX,
            height_cm=settings.SCALE_HEIGHT_CM,
            age=settings.SCALE_AGE,
            is_male=settings.SCALE_SEX != "female",
        )
        self._scan_task: asyncio.Task | None = None
        self._debounce_task: asyncio.Task | None = None
        self._pending: dict[str, Any] | None = None
        self._last_signature: tuple | None = None
        self._last_written: dict[str, Any] | None = None
        self._user_id: int | None = None
        self._profile_height: int = settings.SCALE_HEIGHT_CM
        self._profile_age: int = settings.SCALE_AGE
        self._profile_sex: str = settings.SCALE_SEX

    @property
    def enabled(self) -> bool:
        """是否开启体重秤进程内采集。"""
        return bool(settings.ENABLE_SCALE_COLLECTOR)

    def status(self) -> dict[str, Any]:
        """返回采集器整体状态，供状态接口与问题排查使用。

        Returns:
            开关、蓝牙依赖、扫描任务、用户资料、最近一次写入与读取器状态。
        """
        return {
            "enabled": self.enabled,
            "bleak_available": BLEAK_AVAILABLE,
            "scan_running": self._scan_task is not None and not self._scan_task.done(),
            "user_id": self._user_id,
            "profile": {
                "height_cm": self._profile_height,
                "age": self._profile_age,
                "sex": self._profile_sex,
            },
            "last_written": self._last_written,
            "reader": self._reader.status(),
        }

    async def start(self) -> None:
        """启动体重秤读取与蓝牙扫描（未开启或无蓝牙依赖时直接返回）。"""
        if not self.enabled:
            logger.info("体重秤采集未开启（ENABLE_SCALE_COLLECTOR=false）")
            return
        if not BLEAK_AVAILABLE:
            logger.warning("未安装 bleak 或蓝牙不可用，体重秤采集已跳过")
            return
        if self._scan_task is not None:
            return
        # 先用数据库里的真实资料（身高/年龄/性别）更新读取器，再开始连接
        await asyncio.to_thread(self._load_profile)
        await self._reader.start()
        self._scan_task = asyncio.create_task(self._scan_loop(), name="scale-scan")
        logger.info(
            "体重秤采集任务已创建（资料：%s cm / %s 岁 / %s）",
            self._profile_height,
            self._profile_age,
            self._profile_sex,
        )

    async def stop(self) -> None:
        """停止扫描与读取，并把尚未落库的称重结果补写一次。"""
        task, self._scan_task = self._scan_task, None
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
        debounce, self._debounce_task = self._debounce_task, None
        if debounce is not None:
            debounce.cancel()
            try:
                await debounce
            except asyncio.CancelledError:
                pass
        pending, self._pending = self._pending, None
        if pending is not None:
            await asyncio.to_thread(self._write_measurement, pending)
        await self._reader.stop()

    async def _scan_loop(self) -> None:
        """BLE 扫描主循环：把扫到的候选设备交给读取器，异常时退避重启。"""
        backoff = 5
        while True:
            scanner = None
            try:
                scanner = BleakScanner(  # type: ignore[misc]
                    detection_callback=self._on_advertisement
                )
                await scanner.start()
                logger.info("体重秤扫描已启动（等待 %s* 设备）", settings.SCALE_NAME_PREFIX)
                backoff = 5
                # 扫描持续运行，候选设备由 detection_callback 推送
                await asyncio.sleep(3600)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001 - 扫描异常需重启
                logger.warning("体重秤蓝牙扫描异常：%s，%s 秒后重试", exc, backoff)
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 300)
            finally:
                if scanner is not None:
                    try:
                        await scanner.stop()
                    except Exception:  # noqa: BLE001 - 停止失败不影响重启
                        pass

    def _on_advertisement(self, device: Any, advertisement: Any) -> None:
        """扫描回调：把设备名以配置前缀开头的候选设备报给读取器。

        Args:
            device: bleak 的 BLEDevice。
            advertisement: bleak 的 AdvertisementData。
        """
        name = str(
            getattr(advertisement, "local_name", None)
            or getattr(device, "name", "")
            or ""
        ).strip()
        address = str(getattr(device, "address", "") or "")
        if not address:
            return
        prefix = settings.SCALE_NAME_PREFIX.upper()
        uuids = [
            str(u).lower() for u in (getattr(advertisement, "service_uuids", None) or [])
        ]
        has_scale_service = any("0000ffb0" in u for u in uuids)
        if has_scale_service:
            # 私有服务 FFB0 是该秤最可靠的标识；广播名可能是 "UAF028"（不含 "AFU" 子串）甚至为空，
            # 这里用配置前缀作为登记名，仅供读取器做候选筛选，不影响协议。
            name = settings.SCALE_NAME_PREFIX
        elif not name or prefix not in name.upper():
            return
        rssi = int(getattr(advertisement, "rssi", None) or -100)
        self._reader.note_device(address, name, rssi)

    def _on_event(self, event: dict[str, Any]) -> None:
        """读取器回调：仅接受稳定且合理的称重结果，延迟合并后落库。

        Args:
            event: 读取器解析出的称重事件（含 kg / stable / impedance / body）。
        """
        if not event.get("stable"):
            return
        kg = event.get("kg")
        if not isinstance(kg, (int, float)) or not (
            MIN_WEIGHT_KG <= float(kg) <= MAX_WEIGHT_KG
        ):
            return
        self._pending = event
        if self._debounce_task is None or self._debounce_task.done():
            self._debounce_task = asyncio.create_task(
                self._debounce(), name="scale-persist"
            )

    async def _debounce(self) -> None:
        """等待阻抗包到达后把待落库的称重结果写入数据库。

        稳定体重帧先到、阻抗帧可能晚 1–3 秒到达，因此延迟几秒再写，
        避免同一轮称重产生两次覆盖写入。
        """
        try:
            while True:
                await asyncio.sleep(STABLE_WAIT_SECONDS)
                event, self._pending = self._pending, None
                if event is None:
                    return
                signature = (round(float(event["kg"]), 2), event.get("impedance"))
                if signature == self._last_signature:
                    continue
                await asyncio.to_thread(self._write_measurement, event)
                self._last_signature = signature
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - 落库失败不应拖垮采集任务
            logger.exception("体重秤数据落库失败")
        finally:
            self._debounce_task = None

    def _write_measurement(self, event: dict[str, Any]) -> None:
        """把一次称重写入当天 health_body（存在则覆盖）并记录活动日志。

        Args:
            event: 稳定称重事件。
        """
        db: Session = SessionLocal()
        try:
            user_id = self._resolve_user_id(db)
            if user_id is None:
                logger.warning("系统中没有可归属的用户，体重秤数据暂不落库")
                return
            today = date.today()
            row = db.scalar(
                select(HealthBody)
                .where(
                    HealthBody.user_id == user_id,
                    HealthBody.record_date == today,
                )
                .order_by(HealthBody.id)
                .limit(1)
            )
            created = row is None
            if created:
                row = HealthBody(user_id=user_id, record_date=today)
                db.add(row)

            kg = round(float(event["kg"]), 2)
            row.weight_kg = kg
            if row.gender is None:
                row.gender = self._profile_sex
            if row.height_cm is None:
                row.height_cm = float(self._profile_height)

            body = event.get("body") or {}
            if body:
                self._apply_body(row, body)
            elif row.height_cm:
                # 无阻抗时只更新体重与 BMI，避免沿用上一次（可能是错误体重）的 BMI
                height_m = row.height_cm / 100
                row.bmi = round(kg / (height_m * height_m), 1)

            db.flush()  # 保证新增行拿到 id，供活动日志引用
            detail = {
                "weight_kg": kg,
                "impedance": event.get("impedance"),
                "measured_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "source": "ble-scale",
                "body": body or None,
            }
            db.add(
                ActivityLog(
                    user_id=user_id,
                    action="create" if created else "update",
                    module="health/body",
                    resource_type="body",
                    resource_id=row.id,
                    summary=(
                        f"体重秤自动记录体重 {kg} kg"
                        + ("（含体成分）" if body else "")
                    ),
                    detail=json.dumps(detail, ensure_ascii=False)[:2000],
                    user_agent="ble-scale",
                )
            )
            db.commit()
            self._last_written = {
                "at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "weight_kg": kg,
                "has_body": bool(body),
                "record_date": today.isoformat(),
            }
            logger.info(
                "体重秤已写入当天记录：%.2f kg（%s）", kg, "含体成分" if body else "仅体重"
            )
        except Exception:  # noqa: BLE001 - 落库失败只记录日志
            db.rollback()
            logger.exception("体重秤数据落库失败")
        finally:
            db.close()

    @staticmethod
    def _apply_body(row: HealthBody, body: dict[str, Any]) -> None:
        """把体成分估算结果写入当天记录对应列。

        Args:
            row: 当天的 health_body 记录。
            body: body_composition.calculate() 的返回结果。
        """
        for source_key, column in BODY_FIELD_MAP.items():
            value = body.get(source_key)
            if isinstance(value, (int, float)):
                setattr(row, column, value)

    def _load_profile(self) -> None:
        """从数据库加载用户资料（身高优先取最近体重记录，年龄由生日推算）。"""
        db: Session = SessionLocal()
        try:
            user_id = self._resolve_user_id(db)
            height: float | None = None
            gender: str | None = None
            birthday: date | None = None
            if user_id is not None:
                latest = db.scalar(
                    select(HealthBody)
                    .where(
                        HealthBody.user_id == user_id,
                        HealthBody.height_cm.isnot(None),
                    )
                    .order_by(HealthBody.record_date.desc())
                    .limit(1)
                )
                if latest is not None:
                    height = latest.height_cm
                profile = db.get(UserProfile, user_id)
                if profile is not None:
                    gender = profile.gender
                    birthday = profile.birthday

            self._profile_height = int(height) if height else settings.SCALE_HEIGHT_CM
            sex = (gender or "").lower()
            if sex not in ("male", "female"):
                sex = settings.SCALE_SEX
            self._profile_sex = sex
            if birthday is not None:
                self._profile_age = _calc_age(birthday, date.today()) or settings.SCALE_AGE
            self._reader.set_profile(
                self._profile_height, self._profile_age, self._profile_sex
            )
        except Exception:  # noqa: BLE001 - 资料加载失败时沿用配置默认值
            logger.exception("加载体重秤用户资料失败，沿用配置默认值")
        finally:
            db.close()

    def _resolve_user_id(self, db: Session) -> int | None:
        """解析体重数据归属用户（配置优先，其次取第一个用户），结果缓存。"""
        if self._user_id is not None:
            return self._user_id
        if settings.SCALE_USER_ID:
            self._user_id = int(settings.SCALE_USER_ID)
            return self._user_id
        self._user_id = db.scalar(
            select(UserProfile.id).order_by(UserProfile.id).limit(1)
        )
        return self._user_id


# 模块级单例，由 FastAPI 生命周期统一启动/停止
scale_collector = ScaleWeightCollector()
