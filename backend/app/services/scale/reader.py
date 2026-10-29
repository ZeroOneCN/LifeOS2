#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""蚂蚁阿福体重秤（AFU-WL-TZ-A1）BLE 读取模块。

该秤使用私有服务 0xFFB0（FFB1 写入 / FFB2 通知），无需配对与认证。
实测帧格式（20 字节，包头 0xAC，包类型在 data[18]）：

    体重包(0xD5)  ac 29 <稳定位|00> | <32 位体重编码> | 02 00 | 05 40 | … | 29 d5 | 序号
    阻抗包(0xD6)  ac 29 02 | <通道数> | <2 字节×通道数> | <mode> | <32 位体重编码> | … | 29 d6 | 序号
    资料应答(0xD8) ac 29 01 | … | … | 29 d8 | 序号

体重编码为 32 位大端，低 18 位是克数，bit31 是稳定标志，
bit18-20 是刻度精度（division）。

秤默认只称体重、不做阻抗测量。向 FFB1 下发「时间 + 用户资料」包
（包类型 0xD0，功能位 0x03）后，秤才会在称重结束时测量阻抗并发出
0xD6 阻抗包；随后由 body_composition 用体重与阻抗本地估算身体成分。
"""

from __future__ import annotations

import asyncio
import logging
import sys
import time
from collections.abc import Callable
from typing import Any

from bleak import BleakClient

from .body_composition import calculate

# 体重秤私有服务：写入特征 / 通知特征
FFB1_UUID = "0000ffb1-0000-1000-8000-00805f9b34fb"
FFB2_UUID = "0000ffb2-0000-1000-8000-00805f9b34fb"

# 包类型（位于帧尾倒数第二个字节）
TYPE_WEIGHT = 0xD5
TYPE_IMPEDANCE = 0xD6
TYPE_USER_INFO_ACK = 0xD8

# 默认设备型号字节，收到第一帧后会被真实值覆盖
DEFAULT_DEVICE_TYPE = 0x29
# 合理的克数范围：允许轻微负漂移，上限 250kg
MIN_GRAMS = -800
MAX_GRAMS = 250000
# 候选项的有效期（秒）
CANDIDATE_TTL = 60.0
# 资料包重发间隔（秒），确保秤不会在唤醒后丢失资料
PROFILE_RESEND_SECONDS = 15.0


def _get_int_round(value: float) -> int:
    """复刻 protocol.py 的 _get_int 取整修正。

    Args:
        value: 待取整的浮点数。

    Returns:
        取整后的整数。
    """
    return int(value + 1.0) if (int(value * 10.0) % 10) >= 9 else int(value)


def _gunit(value_kg: float, division: int) -> float:
    """按刻度精度把公斤值换算成秤的显示值。

    Args:
        value_kg: 原始公斤值。
        division: 精度档位（编码的 bit18-20）。

    Returns:
        按该档位取整后的公斤值。
    """
    if division == 0:
        return ((_get_int_round(value_kg * 1000.0) + 5) // 10) / 100.0
    if division == 1:
        raw = _get_int_round(value_kg * 1000.0)
        if raw % 10 == 9:
            raw += 10
        scaled = raw // 10
        if scaled % 2:
            scaled += 1
        return scaled / 100.0
    if division == 2:
        raw = (_get_int_round(value_kg * 1000.0) + 20) // 10
        scaled = (raw // 10) * 10 + 5 if raw % 10 >= 5 else (raw // 10) * 10
        return scaled / 100.0
    if division == 3:
        return ((_get_int_round(value_kg * 100.0) + 5) // 10) / 10.0
    if division == 4:
        raw = _get_int_round(value_kg * 100.0)
        if raw % 10 == 9:
            raw += 10
        scaled = raw // 10
        if scaled % 2:
            scaled += 1
        return scaled / 10.0
    return round(value_kg * 100) / 100


def decode_weight(encoded: int) -> tuple[float, bool, int]:
    """从 32 位体重编码解出体重、稳定标志与克数。

    Args:
        encoded: 32 位大端编码值。

    Returns:
        (体重 kg, 是否稳定, 克数)。
    """
    grams = encoded & 0x3FFFF
    division = (encoded & 0x1C0000) >> 18
    return _gunit(grams / 1000.0, division), bool(encoded & (1 << 31)), grams


def _be16(data: bytes, offset: int) -> int:
    """读取大端 16 位整数。"""
    return (data[offset] << 8) | data[offset + 1]


def _be32(data: bytes, offset: int) -> int:
    """读取大端 32 位整数。"""
    return (
        (data[offset] << 24)
        | (data[offset + 1] << 16)
        | (data[offset + 2] << 8)
        | data[offset + 3]
    )


def parse_frame(raw: bytes) -> dict[str, Any] | None:
    """解析一帧 FFB2 通知。

    Args:
        raw: 通知原始字节。

    Returns:
        解析结果字典，键 type 为 weight / impedance / ack；
        非本秤数据或字段越界时返回 None。
    """
    if len(raw) < 20 or raw[0] != 0xAC:
        return None

    packet_type = raw[18]
    if packet_type == TYPE_WEIGHT:
        kg, stable, grams = decode_weight(_be32(raw, 2))
        return {"type": "weight", "kg": kg, "stable": stable, "grams": grams}

    if packet_type == TYPE_IMPEDANCE:
        # 阻抗包的 data[2] 是通道数，通道值紧跟其后，mode 与体重编码在末尾
        count = raw[2]
        if count <= 0 or 5 + count * 2 + 4 > len(raw):
            return None
        channels = [_be16(raw, 4 + i * 2) for i in range(count)]
        mode = raw[4 + count * 2]
        kg, stable, grams = decode_weight(_be32(raw, 5 + count * 2))
        return {
            "type": "impedance",
            "kg": kg,
            "stable": stable,
            "grams": grams,
            "impedances": channels,
            "mode": mode,
        }

    if packet_type == TYPE_USER_INFO_ACK:
        return {"type": "ack"}

    return None


class ScaleReader:
    """连接体重秤并把重量 / 体成分事件交给回调。

    体重秤平时休眠、停止广播，因此设备由上层扫描回调通过
    :meth:`note_device` 报进来；本类只负责选择候选、连接、下发资料与解析。
    """

    def __init__(
        self,
        on_event: Callable[[dict[str, Any]], None],
        name_prefix: str = "AFU",
        height_cm: int = 173,
        age: int = 25,
        is_male: bool = True,
    ) -> None:
        """初始化读取器。

        Args:
            on_event: 收到测量事件时调用的回调。
            name_prefix: 用于识别体重秤的设备名前缀（不区分大小写）。
            height_cm: 身高（厘米），用于触发阻抗测量与体成分估算。
            age: 年龄（岁）。
            is_male: 是否男性。
        """
        self._on_event = on_event
        self._prefix = (name_prefix or "").strip().upper()
        self.last: dict[str, Any] | None = None
        self.connected = False
        self.error: str | None = None
        self.profile: dict[str, Any] = {
            "height_cm": height_cm,
            "age": age,
            "sex": "male" if is_male else "female",
        }
        self._device_type = DEFAULT_DEVICE_TYPE
        self._candidates: dict[str, tuple[float, str, int]] = {}
        self._address: str | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._wake = asyncio.Event()
        self._done: asyncio.Event | None = None
        self._task: asyncio.Task[None] | None = None
        self._running = False

    async def start(self) -> None:
        """启动后台连接任务。"""
        if self._running:
            return
        self._loop = asyncio.get_running_loop()
        self._running = True
        self._task = asyncio.create_task(self._run())

    async def stop(self) -> None:
        """停止后台任务并断开连接。"""
        self._running = False
        if self._done is not None:
            self._done.set()
        task, self._task = self._task, None
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

    def set_profile(self, height_cm: int, age: int, sex: str) -> None:
        """更新用户资料并重新估算已有测量结果。

        Args:
            height_cm: 身高（厘米）。
            age: 年龄（岁）。
            sex: 性别，male 或 female。
        """
        self.profile = {
            "height_cm": int(height_cm),
            "age": int(age),
            "sex": "female" if str(sex).lower() == "female" else "male",
        }
        if self.last is not None:
            self.last["profile"] = dict(self.profile)
            self._recompute(self.last)

    def note_device(self, address: str, name: str, rssi: int) -> None:
        """登记一个扫描到的候选设备。

        Args:
            address: 设备地址。
            name: 广播中出现的设备名。
            rssi: 信号强度。
        """
        label = (name or "").upper()
        if self._prefix and not label.startswith(self._prefix):
            return
        self._candidates[address] = (time.time(), name, rssi)
        loop = self._loop
        if loop is not None:
            try:
                loop.call_soon_threadsafe(self._wake.set)
            except RuntimeError:
                pass

    def _pick(self) -> str | None:
        """从有效期内的候选中挑选信号最强的一个。

        Returns:
            设备地址；无可用候选时返回 None。
        """
        now = time.time()
        for address in list(self._candidates):
            if now - self._candidates[address][0] > CANDIDATE_TTL:
                self._candidates.pop(address, None)
        if not self._candidates:
            return None
        return max(self._candidates.items(), key=lambda item: item[1][2])[0]

    async def _run(self) -> None:
        """主循环：等待候选设备、连接、断线后重试。"""
        while self._running:
            address = self._pick()
            if address is None:
                self._wake.clear()
                try:
                    await asyncio.wait_for(self._wake.wait(), timeout=3.0)
                except asyncio.TimeoutError:
                    pass
                continue
            try:
                await self._connect_and_read(address)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001
                self.error = f"{type(exc).__name__}: {exc}"
                logging.info("体重秤连接失败：%s", self.error)
                self.connected = False
            else:
                self.error = None
            finally:
                self.connected = False
            if not self._running:
                break
            await asyncio.sleep(2.0)

    def _build_user_info(self) -> bytes:
        """构造「设置时间 + 用户资料」包（0xD0），使能阻抗测量。

        Returns:
            20 字节的资料包。
        """
        packet = [0xAC, self._device_type & 0xFF]
        now = int(time.time())
        packet += [
            (now >> 24) & 0xFF,
            (now >> 16) & 0xFF,
            (now >> 8) & 0xFF,
            now & 0xFF,
        ]
        # 时区，以 15 分钟为单位
        packet.append(int(round(time.localtime().tm_gmtoff / 900)) & 0xFF)
        packet.append(0)  # 单位 0 = kg
        packet.append(1)  # 用户编号
        packet.append(int(self.profile["height_cm"]) & 0xFF)
        packet += [0, 0]  # 档案体重（不填）
        packet.append(int(self.profile["age"]) & 0xFF)
        packet.append(1 if self.profile["sex"] == "male" else 2)
        packet += [0, 0]  # 目标体重（不填）
        packet.append(0x03)  # 功能位：bit0 使能阻抗测量
        packet.append(0)
        packet.append(0xD0)  # 包类型
        packet.append(sum(packet[2:19]) & 0xFF)  # 校验和
        return bytes(packet)

    async def _send_profile_loop(self, client: BleakClient, done: asyncio.Event) -> None:
        """周期性下发用户资料，直到连接断开。

        Args:
            client: 已连接的客户端。
            done: 断线信号。
        """
        while not done.is_set():
            try:
                await client.write_gatt_char(FFB1_UUID, self._build_user_info(), response=False)
            except Exception as exc:  # noqa: BLE001
                logging.debug("下发体重秤资料包失败：%s", exc)
            try:
                await asyncio.wait_for(done.wait(), timeout=PROFILE_RESEND_SECONDS)
            except asyncio.TimeoutError:
                pass

    async def _connect_and_read(self, address: str) -> None:
        """连接指定设备并持续接收通知，直到断开。

        Args:
            address: 设备地址。
        """
        done = asyncio.Event()
        self._done = done

        def on_disconnect(_client: BleakClient) -> None:
            done.set()

        def on_data(_char: Any, data: bytearray) -> None:
            self._handle(bytes(data))

        # winrt 是 Windows 后端专属参数，非 Windows 平台传入会报 TypeError
        client_kwargs: dict[str, Any] = {
            "timeout": 20.0,
            "disconnected_callback": on_disconnect,
        }
        if sys.platform == "win32":
            client_kwargs["winrt"] = {"use_cached_services": False}
        client = BleakClient(address, **client_kwargs)
        await client.connect()
        self._address = address
        self.connected = True
        self.error = None
        logging.info("体重秤已连接：%s（资料 %s）", address, self.profile)

        sender = asyncio.create_task(self._send_profile_loop(client, done))
        try:
            await client.start_notify(FFB2_UUID, on_data)
            await done.wait()
        finally:
            sender.cancel()
            self.connected = False
            try:
                await client.disconnect()
            except Exception:  # noqa: BLE001
                logging.debug("断开体重秤时出现异常", exc_info=True)

    def _recompute(self, event: dict[str, Any]) -> None:
        """用当前资料重新计算事件里的体成分。

        Args:
            event: 需要就地更新的事件字典。
        """
        impedance = event.get("impedance")
        if not impedance or not event.get("stable"):
            return
        event["body"] = calculate(
            weight_kg=event["kg"],
            impedance_ohm=float(impedance),
            height_cm=float(self.profile["height_cm"]),
            age=int(self.profile["age"]),
            is_male=self.profile["sex"] == "male",
        )

    def _handle(self, raw: bytes) -> None:
        """解析通知并广播测量事件。

        Args:
            raw: 通知的原始字节。
        """
        parsed = parse_frame(raw)
        if parsed is None:
            return
        if parsed["type"] == "ack":
            return

        self._device_type = raw[1]
        grams = parsed["grams"]
        if grams < MIN_GRAMS or grams > MAX_GRAMS:
            return

        event: dict[str, Any] = {
            "type": "weight",
            "kg": parsed["kg"],
            "stable": parsed["stable"],
            "grams": grams,
            "address": self._address,
            "profile": dict(self.profile),
            "impedance": None,
            "impedances": [],
            "body": None,
            "ts": round(time.time() * 1000),
        }

        if parsed["type"] == "impedance":
            channels = parsed["impedances"]
            # 通道值为 0 表示本次未形成有效测量回路（如未光脚），按无阻抗处理
            if channels and channels[0] > 0:
                event["impedances"] = channels
                # 多通道时取第一通道作为主阻抗
                event["impedance"] = round(channels[0], 1)
                self._recompute(event)

        self.last = event
        try:
            self._on_event(event)
        except Exception:  # noqa: BLE001
            logging.exception("推送体重事件时出现异常")
