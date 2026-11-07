import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos_mobile/features/health/ble/body_composition.dart';
import 'package:lifeos_mobile/features/health/ble/scale_protocol.dart';

/// 构造一帧体重包（20 字节，稳定位 + 刻度精度 0）。
Uint8List weightFrame(double kg) {
  final int grams = (kg * 1000).round();
  final int encoded = (0x80000000 | grams).toUnsigned(32);
  return Uint8List.fromList(<int>[
    0xac,
    0x29,
    (encoded >> 24) & 0xff,
    (encoded >> 16) & 0xff,
    (encoded >> 8) & 0xff,
    encoded & 0xff,
    0x02,
    0x00,
    0x05,
    0x40,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0xd5,
    0x01,
  ]);
}

/// 构造一帧阻抗包（单通道）。
Uint8List impedanceFrame(double kg, int ohm) {
  final int grams = (kg * 1000).round();
  final int encoded = (0x80000000 | grams).toUnsigned(32);
  return Uint8List.fromList(<int>[
    0xac,
    0x29,
    0x01,
    0x00,
    (ohm >> 8) & 0xff,
    ohm & 0xff,
    0x01,
    (encoded >> 24) & 0xff,
    (encoded >> 16) & 0xff,
    (encoded >> 8) & 0xff,
    encoded & 0xff,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0xd6,
    0x02,
  ]);
}

void main() {
  group('FFB2 帧解析（与网页端 scale-protocol.ts 基准一致）', () {
    test('体重包 73.75 kg 稳定帧解析为 73.756 kg', () {
      final ScaleMeasurement? parsed = parseScaleFrame(weightFrame(73.75));
      expect(parsed, isNotNull);
      expect(parsed!.type, 'weight');
      expect(parsed.weight.grams, 73750);
      expect(parsed.weight.stable, isTrue);
      // TS 基准：decodeWeight(0x80012016) -> 73.756
      expect(parsed.weight.kg, closeTo(73.756, 1e-9));
    });

    test('阻抗包 624 Ω 与 549 Ω 的读数与网页端一致', () {
      for (final (ohm, kg) in <(int, double)>[(624, 73.75), (549, 73.75)]) {
        final ScaleMeasurement? parsed = parseScaleFrame(
          impedanceFrame(kg, ohm),
        );
        expect(parsed, isNotNull);
        expect(parsed!.type, 'impedance');
        expect(parsed.impedances, <int>[ohm]);
        expect(parsed.mode, 0x01);
        expect(parsed.weight.kg, closeTo(73.756, 1e-9));
      }
    });

    test('74.30 kg / 583 Ω 与 536 Ω 两次实测读数一致', () {
      for (final int ohm in <int>[583, 536]) {
        final ScaleMeasurement? parsed = parseScaleFrame(
          impedanceFrame(74.30, ohm),
        );
        expect(parsed!.weight.grams, 74300);
        expect(parsed.weight.kg, closeTo(74.306, 1e-9));
        expect(parsed.impedances, <int>[ohm]);
      }
    });

    test('非法帧返回 null，资料应答包识别为 ack', () {
      expect(parseScaleFrame(Uint8List.fromList(<int>[0xac, 0x29])), isNull);
      expect(
        parseScaleFrame(Uint8List.fromList(List<int>.filled(20, 0x00))),
        isNull,
      );
      final Uint8List channelZero = impedanceFrame(73.75, 0)..[2] = 0x00;
      expect(parseScaleFrame(channelZero), isNull);
      final Uint8List ack = Uint8List.fromList(<int>[
        0xac,
        0x29,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xd8,
        0x03,
      ]);
      expect(parseScaleFrame(ack)?.isAck, isTrue);
    });

    test('非稳定帧不产生稳定标志', () {
      final Uint8List frame = weightFrame(73.75);
      frame[2] = 0x00;
      expect(parseScaleFrame(frame)!.weight.stable, isFalse);
    });
  });

  group('资料包构造', () {
    test('20 字节且字段与校验和符合 TS 实现', () {
      final Uint8List packet = buildScaleUserInfoPacket(
        deviceType: 0x29,
        heightCm: 175,
        age: 30,
        isMale: true,
      );
      expect(packet.length, 20);
      expect(packet[0], 0xac);
      expect(packet[1], 0x29);
      expect(packet[9], 175);
      expect(packet[12], 30);
      expect(packet[13], 1);
      expect(packet[16], 0x03);
      expect(packet[18], 0xd0);
      int sum = 0;
      for (int i = 2; i <= 18; i++) {
        sum += packet[i];
      }
      expect(packet[19], sum & 0xff);
    });
  });

  group('体成分估算（与网页端基准一致）', () {
    test('男 175cm / 30 岁 / 73.75kg / 624Ω 全部字段一致', () {
      final BodyCompositionResult? body = calculateBodyComposition(
        weightKg: 73.75,
        impedanceOhm: 624,
        heightCm: 175,
        age: 30,
        isMale: true,
      );
      expect(body, isNotNull);
      expect(body!.bmi, closeTo(24.1, 1e-9));
      expect(body.bodyFat, closeTo(20.5, 1e-9));
      expect(body.fatMass, closeTo(15.1, 1e-9));
      expect(body.visceralFat, 6);
      expect(body.subFatPct, closeTo(14.6, 1e-9));
      expect(body.subFatMass, closeTo(10.8, 1e-9));
      expect(body.water, closeTo(54.5, 1e-9));
      expect(body.waterMass, closeTo(40.2, 1e-9));
      expect(body.proteinMass, closeTo(13.9, 1e-9));
      expect(body.proteinRate, closeTo(18.9, 1e-9));
      expect(body.bone, closeTo(2.9, 1e-9));
      expect(body.boneRate, closeTo(3.9, 1e-9));
      expect(body.muscle, closeTo(56.1, 1e-9));
      expect(body.muscleRate, closeTo(76.1, 1e-9));
      expect(body.skeletalMuscle, closeTo(31.3, 1e-9));
      expect(body.skeletalMuscleRate, closeTo(42.5, 1e-9));
      expect(body.bmr, 1686);
      expect(body.leanMass, closeTo(58.6, 1e-9));
      expect(body.grades['body_fat'], '偏高');
      expect(body.grades['muscle'], '标准');
    });

    test('女 160cm / 28 岁 / 55.2kg / 549Ω 全部字段一致', () {
      final BodyCompositionResult? body = calculateBodyComposition(
        weightKg: 55.2,
        impedanceOhm: 549,
        heightCm: 160,
        age: 28,
        isMale: false,
      );
      expect(body, isNotNull);
      expect(body!.bmi, closeTo(21.6, 1e-9));
      expect(body.bodyFat, closeTo(30.1, 1e-9));
      expect(body.visceralFat, 5);
      expect(body.subFatMass, closeTo(11.8, 1e-9));
      expect(body.water, closeTo(49.9, 1e-9));
      expect(body.muscle, closeTo(35.8, 1e-9));
      expect(body.skeletalMuscle, closeTo(20.0, 1e-9));
      expect(body.bmr, 1251);
      expect(body.grades['muscle'], '偏低');
    });

    test('资料缺失时不产生占位体成分', () {
      expect(
        calculateBodyComposition(
          weightKg: 55.2,
          impedanceOhm: 549,
          heightCm: 0,
          age: 28,
          isMale: false,
        ),
        isNull,
      );
      expect(
        calculateBodyComposition(
          weightKg: 55.2,
          impedanceOhm: 549,
          heightCm: 160,
          age: 0,
          isMale: false,
        ),
        isNull,
      );
    });

    test('提交体成分时过滤掉 0 值，保留分级字符串', () {
      final BodyCompositionResult body = calculateBodyComposition(
        weightKg: 73.75,
        impedanceOhm: 624,
        heightCm: 175,
        age: 30,
        isMale: true,
      )!;
      final Map<String, dynamic> json = body.toJson();
      expect(
        json.values.whereType<num>().any((num value) => value <= 0),
        isFalse,
      );
      expect(json['grades'], isA<Map<String, String>>());
      expect(json['bmi'], closeTo(24.1, 1e-9));
    });
  });
}
