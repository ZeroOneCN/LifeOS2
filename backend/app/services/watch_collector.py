"""小米手环心率蓝牙采集服务（进程内运行，直接写库）。

不依赖外部桥接进程：随 FastAPI 生命周期启动，使用 bleak 扫描 BLE 广播，
解析心率后按自然日聚合，定期把统计结果直接写入 health_vitals_sleep。

设计要点：
- 每天只维护 1 行聚合数据（样本数 / 最小 / 最大 / 均值），不逐条入库；
- 同一设备最短采样间隔 + 冻结值去抖，避免广播高频与静止值污染均值；
- 数据写入放在线程池，避免阻塞事件循环；
- 未安装 bleak 或没有蓝牙适配器时自动降级，不影响后端其他功能。
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from datetime import date, datetime
from threading import Lock
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.models import ActivityLog, HealthVitalsSleep, UserProfile

try:  # 无蓝牙依赖（未安装 bleak / 系统缺少 WinRT、BlueZ）时安全降级
    from bleak import BleakScanner

    BLEAK_AVAILABLE = True
except Exception:  # noqa: BLE001 - 任何导入失败都视为不可用
    BleakScanner = None  # type: ignore[assignment]
    BLEAK_AVAILABLE = False

logger = logging.getLogger(__name__)

# 小米厂商数据标识（company id）
XIAOMI_COMPANY_ID = 0x0157
# 心率有效区间（bpm），超出视为无效值
HR_MIN_VALID = 20
HR_MAX_VALID = 250
# 标准心率服务 UUID
HR_SERVICE_UUID = "0000180d-0000-1000-8000-00805f9b34fb"


@dataclass
class DayAggregate:
    """单个自然日的心率聚合结果。"""

    record_date: date
    samples: int = 0
    total: float = 0.0
    hr_min: int | None = None
    hr_max: int | None = None
    measured_at: datetime | None = None
    source: str | None = None

    @property
    def hr_avg(self) -> float | None:
        """返回当日有效样本的平均心率（保留 1 位小数），无样本时为 None。"""
        if not self.samples:
            return None
        return round(self.total / self.samples, 1)

    def add(self, bpm: int, at: datetime, source: str) -> None:
        """把一个有效心率样本计入当日聚合。

        Args:
            bpm: 心率值（bpm）。
            at: 采样时间。
            source: 数据来源（xiaomi / standard）。
        """
        self.samples += 1
        self.total += bpm
        self.hr_min = bpm if self.hr_min is None else min(self.hr_min, bpm)
        self.hr_max = bpm if self.hr_max is None else max(self.hr_max, bpm)
        self.measured_at = at
        self.source = source

    def copy(self) -> "DayAggregate":
        """返回当前聚合结果的浅拷贝，供跨线程快照使用。"""
        return DayAggregate(
            record_date=self.record_date,
            samples=self.samples,
            total=self.total,
            hr_min=self.hr_min,
            hr_max=self.hr_max,
            measured_at=self.measured_at,
            source=self.source,
        )


def _signature(day: DayAggregate) -> tuple:
    """生成聚合结果的落库签名，用于跳过没有新样本的重复写入。"""
    return (day.samples, day.hr_min, day.hr_max, day.hr_avg)


class DailyHeartRateAggregator:
    """按自然日聚合心率样本，负责采样节流、冻结值过滤与跨天滚动。"""

    def __init__(self, sample_seconds: int, freeze_minutes: int) -> None:
        """初始化聚合器。

        Args:
            sample_seconds: 同一设备的最小采样间隔（秒），下限 10 秒。
            freeze_minutes: 同一数值持续不变超过该时长视为冻结（分钟）。
        """
        self._sample_seconds = max(10, int(sample_seconds))
        self._freeze_seconds = max(1, int(freeze_minutes)) * 60
        self._lock = Lock()
        self._today = DayAggregate(record_date=datetime.now().date())
        self._previous: list[DayAggregate] = []
        self._last_bpm: int | None = None
        self._last_bpm_changed_at: datetime | None = None
        self._last_sample_at: datetime | None = None

    def feed(self, bpm: int, at: datetime, source: str) -> bool:
        """接收一个心率样本，通过节流与冻结过滤后计入聚合。

        Args:
            bpm: 心率值（bpm）。
            at: 采样时间。
            source: 数据来源（xiaomi / standard）。

        Returns:
            是否被计入当日聚合。
        """
        with self._lock:
            # 跨天滚动：把旧的一天移入待落库队列，重置当日状态
            if at.date() != self._today.record_date:
                self._previous.append(self._today.copy())
                self._today = DayAggregate(record_date=at.date())
                self._last_bpm = None
                self._last_bpm_changed_at = None
                self._last_sample_at = None

            if self._last_bpm != bpm:
                self._last_bpm = bpm
                self._last_bpm_changed_at = at
            elif (
                self._last_bpm_changed_at is not None
                and (at - self._last_bpm_changed_at).total_seconds() > self._freeze_seconds
            ):
                # 数值长时间未变化，判定为手环广播冻结，不计入样本
                return False

            if (
                self._last_sample_at is not None
                and (at - self._last_sample_at).total_seconds() < self._sample_seconds
            ):
                return False

            self._today.add(bpm, at, source)
            self._last_sample_at = at
            return True

    def snapshot(self) -> DayAggregate:
        """返回当日聚合快照。"""
        with self._lock:
            return self._today.copy()

    def take_previous(self) -> list[DayAggregate]:
        """取出跨天待落库的历史日聚合，并清空队列。"""
        with self._lock:
            days = self._previous
            self._previous = []
            return days

    def has_previous(self) -> bool:
        """是否存在跨天待落库的历史日聚合。"""
        with self._lock:
            return bool(self._previous)

    def seed(self, day: DayAggregate) -> None:
        """用数据库已有的当日聚合回灌状态，避免后端重启后均值被重置。

        Args:
            day: 从数据库读出的当日聚合（samples/total/min/max）。
        """
        with self._lock:
            self._today = day.copy()
            self._last_bpm = None
            self._last_bpm_changed_at = None
            self._last_sample_at = None


def decode_heart_rate(
    advertisement: Any, offset: int = 3
) -> tuple[int | None, str | None]:
    """从 BLE 广播中解析心率。

    优先读取小米厂商数据（company id 0x0157）指定偏移处的字节，
    其次兼容标准心率服务（0x180D）的 service data。

    Args:
        advertisement: bleak 的 AdvertisementData 对象。
        offset: 小米厂商数据中“心率字节”的偏移，默认 3。

    Returns:
        (心率值, 来源)；无有效心率时返回 (None, None) 或 (None, 来源)。
    """
    manufacturer = getattr(advertisement, "manufacturer_data", None) or {}
    data = manufacturer.get(XIAOMI_COMPANY_ID)
    if data is not None and len(data) > offset:
        bpm = data[offset]
        # 0xFF 表示手环未开启运动心率，或其他非法值
        if HR_MIN_VALID <= bpm <= HR_MAX_VALID:
            return bpm, "xiaomi"
        return None, "xiaomi"

    service_data = getattr(advertisement, "service_data", None) or {}
    for uuid, raw in service_data.items():
        if str(uuid).lower() != HR_SERVICE_UUID or not raw:
            continue
        flags = raw[0]
        if flags & 0x01 and len(raw) >= 3:
            bpm = raw[1] | (raw[2] << 8)  # 16 位心率（小端）
        elif len(raw) >= 2:
            bpm = raw[1]  # 8 位心率
        else:
            continue
        if HR_MIN_VALID <= bpm <= HR_MAX_VALID:
            return bpm, "standard"
    return None, None


class WatchHeartRateCollector:
    """进程内的心率采集器：BLE 扫描 → 日聚合 → 定时直接落库。"""

    def __init__(self) -> None:
        """按配置初始化采集器（不启动扫描）。"""
        self._aggregator = DailyHeartRateAggregator(
            sample_seconds=settings.WATCH_SAMPLE_SECONDS,
            freeze_minutes=settings.WATCH_FREEZE_MINUTES,
        )
        self._whitelist = [
            item.strip().lower()
            for item in (settings.WATCH_DEVICE or "").split(",")
            if item.strip()
        ]
        self._locked_device: str | None = None
        self._user_id: int | None = None
        self._task: asyncio.Task | None = None
        self._last_persisted: dict[date, tuple] = {}

    @property
    def enabled(self) -> bool:
        """是否开启进程内采集。"""
        return bool(settings.ENABLE_WATCH_COLLECTOR)

    async def start(self) -> None:
        """启动采集任务（未开启或无蓝牙依赖时直接返回）。"""
        if not self.enabled:
            logger.info("手环心率采集未开启（ENABLE_WATCH_COLLECTOR=false）")
            return
        if not BLEAK_AVAILABLE:
            logger.warning("未安装 bleak 或蓝牙不可用，手环心率采集已跳过")
            return
        if self._task is not None:
            return
        await asyncio.to_thread(self._seed_from_db)
        self._task = asyncio.create_task(self._run(), name="watch-hr-collector")
        logger.info("手环心率采集任务已创建")

    async def stop(self) -> None:
        """停止采集任务并做最后一次落库。"""
        task = self._task
        self._task = None
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
        await self._flush()

    async def _run(self) -> None:
        """扫描主循环：BLE 扫描异常时按退避策略重启。"""
        flush_task = asyncio.create_task(self._flush_loop(), name="watch-hr-flush")
        backoff = 5
        try:
            while True:
                scanner = None
                try:
                    scanner = BleakScanner(  # type: ignore[misc]
                        detection_callback=self._on_advertisement
                    )
                    await scanner.start()
                    logger.info("手环心率采集已启动（BLE 扫描中）")
                    backoff = 5
                    # 扫描持续运行，由 detection_callback 推送数据
                    await asyncio.sleep(3600)
                except asyncio.CancelledError:
                    raise
                except Exception as exc:  # noqa: BLE001 - 扫描异常需重启
                    logger.warning("蓝牙扫描异常：%s，%s 秒后重试", exc, backoff)
                    await asyncio.sleep(backoff)
                    backoff = min(backoff * 2, 300)
                finally:
                    if scanner is not None:
                        try:
                            await scanner.stop()
                        except Exception:  # noqa: BLE001 - 停止失败不影响重启
                            pass
        finally:
            flush_task.cancel()
            try:
                await flush_task
            except asyncio.CancelledError:
                pass
            await self._flush()

    async def _flush_loop(self) -> None:
        """定时落库循环：达到间隔或出现跨天数据时写入数据库。"""
        interval = max(10, int(settings.WATCH_FLUSH_INTERVAL))
        tick = min(5, interval)
        elapsed = 0
        while True:
            await asyncio.sleep(tick)
            elapsed += tick
            if elapsed >= interval or self._aggregator.has_previous():
                await self._flush()
                elapsed = 0

    async def _flush(self) -> None:
        """把当日快照与跨天待落库数据写入数据库（仅写有变化的聚合）。"""
        payloads = self._aggregator.take_previous()
        today = self._aggregator.snapshot()
        if today.samples:
            payloads.append(today)
        payloads = [
            day
            for day in payloads
            if self._last_persisted.get(day.record_date) != _signature(day)
        ]
        if not payloads:
            return
        written = await asyncio.to_thread(self._persist, payloads)
        for record_date, signature in written:
            self._last_persisted[record_date] = signature

    def _on_advertisement(self, device: Any, advertisement: Any) -> None:
        """BLE 广播回调：过滤设备、解析心率并送入聚合器。

        Args:
            device: bleak 的 BLEDevice。
            advertisement: bleak 的 AdvertisementData。
        """
        address = str(getattr(device, "address", "") or "").lower()
        name = str(
            getattr(advertisement, "local_name", None)
            or getattr(device, "name", "")
            or ""
        )
        haystack = f"{address} {name.lower()}"

        if self._whitelist and not any(k in haystack for k in self._whitelist):
            return

        bpm, source = decode_heart_rate(advertisement, settings.WATCH_HR_OFFSET)
        if bpm is None:
            return

        device_key = address or haystack.strip()
        if self._locked_device is None:
            # 未配置白名单时，锁定首个上报有效心率的设备，避免多设备数据混在一起
            self._locked_device = device_key
            logger.info("已锁定心率设备：%s（%s）", name or device_key, device_key)
        elif self._locked_device != device_key:
            return

        self._aggregator.feed(bpm, datetime.now(), source or "xiaomi")

    def _persist(self, payloads: list[DayAggregate]) -> list[tuple[date, tuple]]:
        """把聚合结果写入 health_vitals_sleep（按用户 + 日期幂等 upsert）。

        Args:
            payloads: 需要落库的日聚合列表。

        Returns:
            成功写入的 (日期, 落库签名) 列表。
        """
        db: Session = SessionLocal()
        written: list[tuple[date, tuple]] = []
        try:
            user_id = self._resolve_user_id(db)
            if user_id is None:
                logger.warning("系统中没有可归属的用户，手环心率暂不落库")
                return []
            for day in payloads:
                row = db.scalar(
                    select(HealthVitalsSleep)
                    .where(
                        HealthVitalsSleep.user_id == user_id,
                        HealthVitalsSleep.record_date == day.record_date,
                    )
                    .order_by(HealthVitalsSleep.id)
                    .limit(1)
                )
                if row is None:
                    row = HealthVitalsSleep(
                        user_id=user_id, record_date=day.record_date
                    )
                    db.add(row)
                # heart_rate 与心率趋势口径一致：记录当日有效样本均值
                if day.hr_avg is not None:
                    row.heart_rate = int(round(day.hr_avg))
                row.hr_min = day.hr_min
                row.hr_max = day.hr_max
                row.hr_avg = day.hr_avg
                row.hr_samples = day.samples
                row.hr_source = day.source
                row.hr_measured_at = day.measured_at
                db.flush()  # 保证新增行拿到 id，活动日志按当天行 id 归属
                # 每天只保留 1 条采集日志：后续落库用最新数据覆盖内容，避免活动日志爆炸
                summary = (
                    f"手环采集心率 {day.hr_avg} bpm"
                    f"（今日 {day.samples} 个样本，{day.hr_min}~{day.hr_max}）"
                )
                detail = json.dumps(
                    {
                        "record_date": day.record_date.isoformat(),
                        "hr_avg": day.hr_avg,
                        "hr_min": day.hr_min,
                        "hr_max": day.hr_max,
                        "samples": day.samples,
                        "source": day.source,
                        "measured_at": (
                            day.measured_at.strftime("%Y-%m-%d %H:%M:%S")
                            if day.measured_at
                            else None
                        ),
                        "device": "ble-watch",
                    },
                    ensure_ascii=False,
                )[:2000]
                log = db.scalar(
                    select(ActivityLog)
                    .where(
                        ActivityLog.user_id == user_id,
                        ActivityLog.module == "health/vitals-sleep",
                        ActivityLog.resource_id == row.id,
                    )
                    .order_by(ActivityLog.id)
                    .limit(1)
                )
                if log is None:
                    db.add(
                        ActivityLog(
                            user_id=user_id,
                            action="create",
                            module="health/vitals-sleep",
                            resource_type="vitals",
                            resource_id=row.id,
                            summary=summary,
                            detail=detail,
                            user_agent="ble-watch",
                        )
                    )
                else:
                    log.action = "update"
                    log.summary = summary
                    log.detail = detail
                written.append((day.record_date, _signature(day)))
            db.commit()
            return written
        except Exception:  # noqa: BLE001 - 落库失败不应拖垮采集任务
            db.rollback()
            logger.exception("手环心率落库失败")
            return []
        finally:
            db.close()

    def _resolve_user_id(self, db: Session) -> int | None:
        """解析心率数据归属用户（配置优先，其次取第一个用户），结果缓存。"""
        if self._user_id is not None:
            return self._user_id
        if settings.WATCH_USER_ID:
            self._user_id = int(settings.WATCH_USER_ID)
            return self._user_id
        self._user_id = db.scalar(select(UserProfile.id).order_by(UserProfile.id).limit(1))
        return self._user_id

    def _seed_from_db(self) -> None:
        """启动时从数据库回灌当日聚合，避免后端重启导致当日均值被清零重算。"""
        db: Session = SessionLocal()
        try:
            user_id = self._resolve_user_id(db)
            if user_id is None:
                return
            today = datetime.now().date()
            row = db.scalar(
                select(HealthVitalsSleep)
                .where(
                    HealthVitalsSleep.user_id == user_id,
                    HealthVitalsSleep.record_date == today,
                )
                .order_by(HealthVitalsSleep.id)
                .limit(1)
            )
            if row is None or not row.hr_samples or row.hr_avg is None:
                return
            day = DayAggregate(
                record_date=today,
                samples=int(row.hr_samples),
                total=float(row.hr_samples) * float(row.hr_avg),
                hr_min=row.hr_min,
                hr_max=row.hr_max,
                measured_at=row.hr_measured_at,
                source=row.hr_source,
            )
            self._aggregator.seed(day)
            self._last_persisted[today] = _signature(day)
            logger.info(
                "已回灌当日心率聚合：%s 个样本，均值 %s bpm", day.samples, day.hr_avg
            )
        except Exception:  # noqa: BLE001 - 回灌失败时从零开始采集
            logger.exception("回灌当日心率聚合失败")
        finally:
            db.close()


# 模块级单例，由 FastAPI 生命周期统一启动/停止
watch_collector = WatchHeartRateCollector()
