/// 蚂蚁阿福体重秤（AFU-WL-TZ-A1）私有 BLE 协议解析。
///
/// 严格移植仓库现有实现，帧格式、取整与校验规则保持一致：
/// - `frontend/src/lib/bluetooth/scale-protocol.ts`
/// - `backend/app/services/scale/reader.py`
///
/// 私有服务 `0xFFB0`（`FFB1` 写入 / `FFB2` 通知），无需配对与认证。
/// 帧为 20 字节，包头 0xAC，包类型位于 `data[18]`：
/// - 体重包(0xD5)：`ac 29 <稳定位|00> <32 位体重编码> ... 29 d5 <序号>`
/// - 阻抗包(0xD6)：`ac 29 <通道数> <2 字节×通道数> <mode> <32 位体重编码> ... 29 d6`
/// - 资料应答(0xD8)
///
/// 体重编码为 32 位大端：低 18 位为克数，bit31 为稳定标志，
/// bit18-20 为刻度精度（division）。
library;

import 'dart:typed_data';

/// 体重秤私有服务 UUID。
const String scaleServiceUuid = '0000ffb0-0000-1000-8000-00805f9b34fb';

/// 写入特征（下发「时间 + 用户资料」包）。
const String scaleWriteUuid = '0000ffb1-0000-1000-8000-00805f9b34fb';

/// 通知特征（体重 / 阻抗数据）。
const String scaleNotifyUuid = '0000ffb2-0000-1000-8000-00805f9b34fb';

/// 体重包类型。
const int scaleTypeWeight = 0xd5;

/// 阻抗包类型。
const int scaleTypeImpedance = 0xd6;

/// 资料应答包类型。
const int scaleTypeAck = 0xd8;

/// 默认设备型号字节；收到首帧后被真实值覆盖。
const int scaleDefaultDeviceType = 0x29;

/// 合理克数下限（允许轻微负漂移）。
const int scaleMinGrams = -800;

/// 合理克数上限（250 kg）。
const int scaleMaxGrams = 250000;

/// 体重解析结果。
class ScaleWeight {
  const ScaleWeight({
    required this.kg,
    required this.stable,
    required this.grams,
  });

  /// 换算后的体重（kg）。
  final double kg;

  /// 秤面是否已稳定。
  final bool stable;

  /// 原始克数。
  final int grams;
}

/// 一帧通知的解析结果。
class ScaleMeasurement {
  const ScaleMeasurement({
    required this.type,
    required this.weight,
    this.impedances,
    this.mode,
  });

  /// `weight` / `impedance` / `ack`。
  final String type;
  final ScaleWeight weight;

  /// 阻抗通道值（仅阻抗包）。
  final List<int>? impedances;

  /// 阻抗模式（仅阻抗包）。
  final int? mode;

  bool get isWeight => type == 'weight';
  bool get isImpedance => type == 'impedance';
  bool get isAck => type == 'ack';
}

/// 复刻 TS 版本 `getIntRound`：`Math.floor(value + 1.0)`。
///
/// 注意：后端 Python 的同名函数带条件分支，division 0 时比 TS 少 0.006 kg。
/// 移动端按「与网页端一致」的要求采用 TS 语义。
int _getIntRound(double value) => (value + 1.0).floor();

/// 按刻度精度把公斤值换算成秤的显示值。
double _gunit(double valueKg, int division) {
  switch (division) {
    case 0:
      return ((_getIntRound(valueKg * 1000) + 5) / 10) / 100.0;
    case 1:
      int raw = _getIntRound(valueKg * 1000);
      if (raw % 10 == 9) {
        raw += 10;
      }
      final double scaled = raw / 10;
      return (scaled % 2 != 0 ? scaled + 1 : scaled) / 100.0;
    case 2:
      final double raw = (_getIntRound(valueKg * 1000) + 20) / 10;
      final int scaled = raw % 10 >= 5
          ? (raw / 10).floor() * 10 + 5
          : (raw / 10).floor() * 10;
      return scaled / 100.0;
    case 3:
      return ((_getIntRound(valueKg * 100) + 5) / 10) / 10.0;
    case 4:
      int raw = _getIntRound(valueKg * 100);
      if (raw % 10 == 9) {
        raw += 10;
      }
      final double scaled = raw / 10;
      return (scaled % 2 != 0 ? scaled + 1 : scaled) / 10.0;
    default:
      return (valueKg * 100).round() / 100.0;
  }
}

/// 从 32 位体重编码解出体重、稳定标志与克数。
ScaleWeight decodeScaleWeight(int encoded) {
  final int grams = encoded & 0x3ffff;
  final int division = (encoded & 0x1c0000) >> 18;
  return ScaleWeight(
    kg: _gunit(grams / 1000.0, division),
    stable: encoded & (1 << 31) != 0,
    grams: grams,
  );
}

/// 读取大端 16 位整数。
int _be16(Uint8List data, int offset) => (data[offset] << 8) | data[offset + 1];

/// 读取大端 32 位整数。
int _be32(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

/// 解析一帧 FFB2 通知；非本秤数据或字段越界返回 null。
ScaleMeasurement? parseScaleFrame(Uint8List raw) {
  if (raw.length < 20 || raw[0] != 0xac) {
    return null;
  }
  final int packetType = raw[18];

  if (packetType == scaleTypeWeight) {
    return ScaleMeasurement(
      type: 'weight',
      weight: decodeScaleWeight(_be32(raw, 2)),
    );
  }

  if (packetType == scaleTypeImpedance) {
    final int count = raw[2];
    if (count <= 0 || 5 + count * 2 + 4 > raw.length) {
      return null;
    }
    final List<int> channels = <int>[
      for (int i = 0; i < count; i++) _be16(raw, 4 + i * 2),
    ];
    final int mode = raw[4 + count * 2];
    return ScaleMeasurement(
      type: 'impedance',
      weight: decodeScaleWeight(_be32(raw, 5 + count * 2)),
      impedances: channels,
      mode: mode,
    );
  }

  if (packetType == scaleTypeAck) {
    return const ScaleMeasurement(
      type: 'ack',
      weight: ScaleWeight(kg: 0, stable: false, grams: 0),
    );
  }

  return null;
}

/// 构造「设置时间 + 用户资料」包（0xD0），使能阻抗测量。
///
/// 与 TS `buildUserInfoPacket` / Python `_build_user_info` 字节级一致：
/// 20 字节，索引 0-18 为数据，第 19 字节为索引 2-18 的校验和。
Uint8List buildScaleUserInfoPacket({
  required int deviceType,
  required int heightCm,
  required int age,
  required bool isMale,
}) {
  final List<int> packet = <int>[0xac, deviceType & 0xff];
  final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  packet
    ..addAll(<int>[
      (now >> 24) & 0xff,
      (now >> 16) & 0xff,
      (now >> 8) & 0xff,
      now & 0xff,
    ])
    // 时区偏移，以 15 分钟为单位（东八区为 32）。
    ..add((DateTime.now().timeZoneOffset.inMinutes / 15).round() & 0xff)
    ..add(0) // 单位 0 = kg
    ..add(1) // 用户编号
    ..add(heightCm & 0xff)
    ..addAll(<int>[0, 0]) // 档案体重（不填）
    ..add(age & 0xff)
    ..add(isMale ? 1 : 2)
    ..addAll(<int>[0, 0]) // 目标体重（不填）
    ..add(0x03) // 功能位：bit0 使能阻抗测量
    ..add(0)
    ..add(0xd0); // 包类型

  int sum = 0;
  for (int i = 2; i <= 18; i++) {
    sum += packet[i];
  }
  packet.add(sum & 0xff);
  return Uint8List.fromList(packet);
}

/// 克数是否在合理范围（超出视为误读）。
bool isValidScaleGrams(int grams) =>
    grams >= scaleMinGrams && grams <= scaleMaxGrams;
