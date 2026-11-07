/// 身体成分估算（BIA 生物电阻抗分析）。
///
/// 移植自 `frontend/src/lib/bluetooth/body-composition.ts`，
/// 该 TS 版本又移植自 `backend/app/services/scale/body_composition.py`。
/// 结果均为估算值，不能用于医学诊断。
library;

/// 阻抗无效时的兜底值（欧姆）。
const double _fallbackImpedance = 500.0;

/// 皮下脂肪系数。
const double _subFatCoeff = 0.71;

/// 骨骼肌系数。
const double _skeletalMuscleCoeff = 0.558;

/// 蛋白质系数。
const double _proteinCoeff = 0.238;

/// 体脂率分级阈值：(性别, 年龄下限, 年龄上限) → (偏低上限, 标准上限, 偏高水平上限)。
const Map<String, List<double>> _fatRanges = <String, List<double>>{
  'male:18-39': <double>[11.0, 17.0, 22.0],
  'male:40-59': <double>[12.0, 18.0, 23.0],
  'male:60+': <double>[14.0, 20.0, 25.0],
  'female:18-39': <double>[21.0, 28.0, 35.0],
  'female:40-59': <double>[22.0, 29.0, 36.0],
  'female:60+': <double>[23.0, 30.0, 37.0],
};

/// 骨骼肌参考值（Janssen MRI 研究）。
const Map<String, double> _skeletalMuscleRef = <String, double>{
  'male': 33.0,
  'female': 21.0,
};

/// 体成分估算结果（字段名与网页端提交给 `blesync` 的键一致）。
class BodyCompositionResult {
  const BodyCompositionResult({
    required this.bmi,
    required this.bodyFat,
    required this.fatMass,
    required this.visceralFat,
    required this.subFatPct,
    required this.subFatMass,
    required this.water,
    required this.waterMass,
    required this.proteinMass,
    required this.proteinRate,
    required this.bone,
    required this.boneRate,
    required this.muscle,
    required this.muscleRate,
    required this.skeletalMuscle,
    required this.skeletalMuscleRate,
    required this.bmr,
    required this.leanMass,
    required this.grades,
  });

  final double bmi;
  final double bodyFat;
  final double fatMass;
  final int visceralFat;
  final double subFatPct;
  final double subFatMass;
  final double water;
  final double waterMass;
  final double proteinMass;
  final double proteinRate;
  final double bone;
  final double boneRate;
  final double muscle;
  final double muscleRate;
  final double skeletalMuscle;
  final double skeletalMuscleRate;
  final int bmr;
  final double leanMass;
  final Map<String, String> grades;

  /// 提交给后端的体成分对象。
  ///
  /// 与网页端一致保留全部键；后端只取能映射到列的数值项。
  /// 0 值按「未采集」处理，这里过滤掉，避免把 0 写进库。
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'bmi': bmi,
      'body_fat': bodyFat,
      'fat_mass': fatMass,
      'visceral_fat': visceralFat,
      'sub_fat_pct': subFatPct,
      'sub_fat_mass': subFatMass,
      'water': water,
      'water_mass': waterMass,
      'protein_mass': proteinMass,
      'protein_rate': proteinRate,
      'bone': bone,
      'bone_rate': boneRate,
      'muscle': muscle,
      'muscle_rate': muscleRate,
      'skeletal_muscle': skeletalMuscle,
      'skeletal_muscle_rate': skeletalMuscleRate,
      'bmr': bmr,
      'lean_mass': leanMass,
      'grades': grades,
    };
    json.removeWhere(
      (String _, dynamic value) => value is num ? value <= 0 : value == null,
    );
    return json;
  }
}

/// 体脂率分级区间。
List<double> _fatRange(bool isMale, int age) {
  final String sex = isMale ? 'male' : 'female';
  if (age >= 60) {
    return _fatRanges['$sex:60+']!;
  }
  if (age >= 40) {
    return _fatRanges['$sex:40-59']!;
  }
  return _fatRanges['$sex:18-39']!;
}

/// 体脂率分级。
String _gradeFat(double value, bool isMale, int age) {
  final List<double> range = _fatRange(isMale, age);
  if (value < range[0]) {
    return '偏低';
  }
  if (value < range[1]) {
    return '标准';
  }
  if (value < range[2]) {
    return '偏高';
  }
  return '过高';
}

/// 骨量参考区间（按性别与体重）。
List<double> _boneRange(bool isMale, double weightKg) {
  if (isMale) {
    if (weightKg >= 75) {
      return <double>[2.0, 4.2];
    }
    if (weightKg >= 60) {
      return <double>[1.9, 4.1];
    }
    return <double>[1.6, 3.9];
  }
  if (weightKg >= 60) {
    return <double>[1.8, 3.9];
  }
  if (weightKg >= 45) {
    return <double>[1.5, 3.8];
  }
  return <double>[1.3, 3.6];
}

/// 肌肉量参考区间（按性别与身高）。
List<double> _muscleRange(bool isMale, double heightCm) {
  if (isMale) {
    if (heightCm >= 170) {
      return <double>[49.4, 59.5];
    }
    if (heightCm >= 160) {
      return <double>[44.0, 52.5];
    }
    return <double>[38.5, 46.6];
  }
  if (heightCm >= 160) {
    return <double>[36.5, 42.6];
  }
  if (heightCm >= 150) {
    return <double>[32.9, 37.6];
  }
  return <double>[29.1, 34.8];
}

/// 区间分级：低于下限偏低、不超过上限标准、否则偏高。
String _band(double value, double low, double high) {
  if (value < low) {
    return '偏低';
  }
  if (value <= high) {
    return '标准';
  }
  return '偏高';
}

/// 水分分级。
String _waterGrade(double value, bool isMale) {
  final List<double> range = isMale
      ? const <double>[50.0, 65.0]
      : const <double>[45.0, 60.0];
  return _band(value, range[0], range[1]);
}

/// 保留 [digits] 位小数的四舍五入（与 JS `Math.round(x*n)/n` 等价）。
double _round(double value, int digits) {
  final double factor = digits == 1 ? 10 : (digits == 2 ? 100 : 1);
  return (value * factor).round() / factor;
}

/// 根据体重、阻抗与用户资料估算身体成分。
///
/// 参数无有效值（体重 / 身高 / 年龄 <= 0）时返回 null，不产生占位数据。
BodyCompositionResult? calculateBodyComposition({
  required double weightKg,
  required double impedanceOhm,
  required double heightCm,
  required int age,
  required bool isMale,
}) {
  if (weightKg <= 0 || heightCm <= 0 || age <= 0) {
    return null;
  }

  final double height = heightCm;
  final int years = age;
  final double impedance = impedanceOhm > 0 ? impedanceOhm : _fallbackImpedance;

  final double bmi = weightKg / ((height / 100) * (height / 100));

  // 瘦体重系数（LBM coefficient）
  final double lbm =
      (height * 9.058 / 100) * (height / 100) +
      weightKg * 0.32 +
      12.226 -
      impedance * 0.0068 -
      years * 0.0542;

  // 体脂率
  double fatCoeff = 1.0;
  double fatConst;
  if (isMale) {
    fatConst = 0.8;
    if (weightKg < 61) {
      fatCoeff = 0.98;
    }
    if (height > 160) {
      fatCoeff *= 1.03;
    }
  } else {
    fatConst = age <= 49 ? 9.25 : 7.25;
    if (weightKg > 60) {
      fatCoeff = 0.96;
    } else if (weightKg < 50) {
      fatCoeff = 1.02;
    }
    if (height > 160) {
      fatCoeff *= 1.03;
    }
  }

  double fatPct = (1.0 - ((lbm - fatConst) * fatCoeff) / weightKg) * 100;
  fatPct = fatPct.clamp(3.0, 60.0).toDouble();

  // 水分率
  double waterPct = (100.0 - fatPct) * 0.7;
  final double waterCoeff = waterPct <= 50 ? 1.02 : 0.98;
  waterPct = (waterPct * waterCoeff).clamp(35.0, 75.0).toDouble();

  // 骨量（kg）
  double bone = isMale
      ? -(0.18016894 - lbm * 0.05158)
      : -(0.245691014 - lbm * 0.07158);
  bone += bone > 2.2 ? 0.1 : -0.1;
  bone = bone.clamp(0.5, double.infinity).toDouble();

  final double fatMass = (fatPct / 100) * weightKg;
  final double muscleMass = weightKg - fatMass - bone * 0.85;
  final double muscleRate = (muscleMass / weightKg) * 100;
  final double leanMass = weightKg - fatMass;

  // 内脏脂肪等级
  double visceral = bmi * 0.3 - years * 0.05 + 0.4;
  final int visceralInt = visceral.round().clamp(1, 50).toInt();

  // 皮下脂肪
  final double subPct = fatPct * _subFatCoeff;

  // 蛋白质
  final double proteinMass = leanMass * _proteinCoeff;
  final double proteinRate = (proteinMass / weightKg) * 100;

  // 骨骼肌
  final double skeletal = muscleMass * _skeletalMuscleCoeff;
  final double skeletalRate = (skeletal / weightKg) * 100;
  final double skeletalRef = _skeletalMuscleRef[isMale ? 'male' : 'female']!;

  // 基础代谢（Mifflin-St Jeor）
  final int bmr =
      (isMale
              ? 10 * weightKg + 6.25 * height - 5 * years + 5
              : 10 * weightKg + 6.25 * height - 5 * years - 161)
          .round();

  final String fatGrade = _gradeFat(fatPct, isMale, age);
  final List<double> muscleBand = _muscleRange(isMale, height);
  final String muscleGradeRaw = _band(muscleMass, muscleBand[0], muscleBand[1]);
  final String muscleGrade = muscleGradeRaw == '偏高' ? '优秀' : muscleGradeRaw;
  final List<double> fatRange = _fatRange(isMale, age);
  final List<double> boneBand = _boneRange(isMale, weightKg);

  return BodyCompositionResult(
    bmi: _round(bmi, 1),
    bodyFat: _round(fatPct, 1),
    fatMass: _round(fatMass, 1),
    visceralFat: visceralInt,
    subFatPct: _round(subPct, 1),
    subFatMass: _round(weightKg * subPct * 0.01, 1),
    water: _round(waterPct, 1),
    waterMass: _round(weightKg * waterPct * 0.01, 1),
    proteinMass: _round(proteinMass, 1),
    proteinRate: _round(proteinRate, 1),
    bone: _round(bone, 2),
    boneRate: _round((bone / weightKg) * 100, 1),
    muscle: _round(muscleMass, 1),
    muscleRate: _round(muscleRate, 1),
    skeletalMuscle: _round(skeletal, 1),
    skeletalMuscleRate: _round(skeletalRate, 1),
    bmr: bmr,
    leanMass: _round(leanMass, 1),
    grades: <String, String>{
      'visceral_fat': visceralInt <= 9 ? '标准' : '高',
      'body_fat': fatGrade,
      'fat_mass': fatGrade,
      'sub_fat': _band(
        subPct,
        fatRange[0] * _subFatCoeff,
        fatRange[1] * _subFatCoeff,
      ),
      'bone': _band(bone, boneBand[0], boneBand[1]),
      'water': _waterGrade(waterPct, isMale),
      'water_mass': _waterGrade(waterPct, isMale),
      'protein': proteinRate < 16 ? '不足' : (proteinRate > 20 ? '优秀' : '标准'),
      'muscle': muscleGrade,
      'muscle_rate': muscleGrade,
      'skeletal_muscle': _band(skeletal, skeletalRef * 0.9, skeletalRef * 1.1),
      'skeletal_muscle_rate': _band(
        skeletal,
        skeletalRef * 0.9,
        skeletalRef * 1.1,
      ),
    },
  );
}
