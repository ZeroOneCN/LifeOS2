/**
 * 身体成分估算（BIA 生物电阻抗分析）。
 *
 * 移植自 backend/app/services/scale/body_composition.py
 *
 * 基础公式来自 ha-miscale2 / icomon_scale（经 ant-afu-scale 的 BodyComposition.swift 复刻）。
 * 结果均为估算值，不能用于医学诊断。
 */

// 阻抗无效时的兜底值
const FALLBACK_IMPEDANCE = 500.0

// 体脂率分级阈值：(性别, 年龄下限, 年龄上限) -> (偏低上限, 标准上限, 偏高水平上限)
const FAT_RANGES: Record<string, [number, number, number]> = {
  'male:18-39': [11.0, 17.0, 22.0],
  'male:40-59': [12.0, 18.0, 23.0],
  'male:60+': [14.0, 20.0, 25.0],
  'female:18-39': [21.0, 28.0, 35.0],
  'female:40-59': [22.0, 29.0, 36.0],
  'female:60+': [23.0, 30.0, 37.0],
}

/** 皮下脂肪系数 */
const SUB_FAT_COEFF = 0.71
/** 骨骼肌系数 */
const SKELETAL_MUSCLE_COEFF = 0.558
/** 蛋白质系数 */
const PROTEIN_COEFF = 0.238
/** 骨骼肌参考值（Janssen MRI 研究） */
const SKELETAL_MUSCLE_REF = { male: 33.0, female: 21.0 }

/** 体成分估算结果 */
export interface BodyComposition {
  bmi: number
  body_fat: number
  fat_mass: number
  visceral_fat: number
  sub_fat_pct: number
  sub_fat_mass: number
  water: number
  water_mass: number
  protein_mass: number
  protein_rate: number
  bone: number
  bone_rate: number
  muscle: number
  muscle_rate: number
  skeletal_muscle: number
  skeletal_muscle_rate: number
  bmr: number
  lean_mass: number
  grades: Record<string, string>
}

function fatRange(isMale: boolean, age: number): [number, number, number] {
  const sex = isMale ? 'male' : 'female'
  if (age >= 60) return FAT_RANGES[`${sex}:60+`]
  if (age >= 40) return FAT_RANGES[`${sex}:40-59`]
  return FAT_RANGES[`${sex}:18-39`]
}

function gradeFat(value: number, isMale: boolean, age: number): string {
  const [low, mid, high] = fatRange(isMale, age)
  if (value < low) return '偏低'
  if (value < mid) return '标准'
  if (value < high) return '偏高'
  return '过高'
}

function boneRange(isMale: boolean, weightKg: number): [number, number] {
  if (isMale) {
    if (weightKg >= 75) return [2.0, 4.2]
    if (weightKg >= 60) return [1.9, 4.1]
    return [1.6, 3.9]
  }
  if (weightKg >= 60) return [1.8, 3.9]
  if (weightKg >= 45) return [1.5, 3.8]
  return [1.3, 3.6]
}

function muscleRange(isMale: boolean, heightCm: number): [number, number] {
  if (isMale) {
    if (heightCm >= 170) return [49.4, 59.5]
    if (heightCm >= 160) return [44.0, 52.5]
    return [38.5, 46.6]
  }
  if (heightCm >= 160) return [36.5, 42.6]
  if (heightCm >= 150) return [32.9, 37.6]
  return [29.1, 34.8]
}

function band(value: number, low: number, high: number): string {
  if (value < low) return '偏低'
  if (value <= high) return '标准'
  return '偏高'
}

function waterGrade(value: number, isMale: boolean): string {
  const [low, high] = isMale ? [50.0, 65.0] : [45.0, 60.0]
  return band(value, low, high)
}

/**
 * 根据体重、阻抗与用户资料估算身体成分。
 *
 * @param weightKg 体重（kg）
 * @param impedanceOhm 阻抗（欧姆）
 * @param heightCm 身高（cm）
 * @param age 年龄（岁）
 * @param isMale 是否男性
 */
export function calculateBodyComposition(
  weightKg: number,
  impedanceOhm: number,
  heightCm: number,
  age: number,
  isMale: boolean,
): BodyComposition | null {
  if (weightKg <= 0 || heightCm <= 0 || age <= 0) return null

  const height = heightCm
  const years = age
  const impedance = impedanceOhm > 0 ? impedanceOhm : FALLBACK_IMPEDANCE

  const bmi = weightKg / (height / 100) ** 2

  // 瘦体重系数（LBM coefficient）
  const lbm =
    (height * 9.058 / 100) * (height / 100) +
    weightKg * 0.32 +
    12.226 -
    impedance * 0.0068 -
    years * 0.0542

  // 体脂率
  let fatCoeff = 1.0
  let fatConst = 0.0
  if (isMale) {
    fatConst = 0.8
    if (weightKg < 61) fatCoeff = 0.98
    if (height > 160) fatCoeff *= 1.03
  } else {
    fatConst = age <= 49 ? 9.25 : 7.25
    if (weightKg > 60) fatCoeff = 0.96
    else if (weightKg < 50) fatCoeff = 1.02
    if (height > 160) fatCoeff *= 1.03
  }

  let fatPct = (1.0 - ((lbm - fatConst) * fatCoeff) / weightKg) * 100
  fatPct = Math.min(60.0, Math.max(3.0, fatPct))

  // 水分率
  let waterPct = (100.0 - fatPct) * 0.7
  const waterCoeff = waterPct <= 50 ? 1.02 : 0.98
  waterPct = Math.min(75.0, Math.max(35.0, waterPct * waterCoeff))

  // 骨量（kg）
  let bone: number
  if (isMale) {
    bone = -(0.18016894 - lbm * 0.05158)
  } else {
    bone = -(0.245691014 - lbm * 0.07158)
  }
  bone += bone > 2.2 ? 0.1 : -0.1
  bone = Math.max(0.5, bone)

  const fatMass = (fatPct / 100) * weightKg
  const muscleMass = weightKg - fatMass - bone * 0.85
  const muscleRate = (muscleMass / weightKg) * 100
  const leanMass = weightKg - fatMass

  // 内脏脂肪等级
  let visceral = bmi * 0.3 - years * 0.05 + 0.4
  visceral = Math.min(50, Math.max(1, Math.round(visceral)))

  // 皮下脂肪
  const subPct = fatPct * SUB_FAT_COEFF

  // 蛋白质
  const proteinMass = leanMass * PROTEIN_COEFF
  const proteinRate = (proteinMass / weightKg) * 100

  // 骨骼肌
  const skeletal = muscleMass * SKELETAL_MUSCLE_COEFF
  const skeletalRate = (skeletal / weightKg) * 100
  const skeletalRef = SKELETAL_MUSCLE_REF[isMale ? 'male' : 'female']

  // 基础代谢（Mifflin-St Jeor）
  const bmr = isMale
    ? 10 * weightKg + 6.25 * height - 5 * years + 5
    : 10 * weightKg + 6.25 * height - 5 * years - 161

  const fatGrade = gradeFat(fatPct, isMale, age)
  const muscleBand = band(muscleMass, ...muscleRange(isMale, height))
  const muscleGrade = muscleBand === '偏高' ? '优秀' : muscleBand
  const [fatLow, fatMid] = fatRange(isMale, age)

  return {
    bmi: Math.round(bmi * 10) / 10,
    body_fat: Math.round(fatPct * 10) / 10,
    fat_mass: Math.round(fatMass * 10) / 10,
    visceral_fat: visceral,
    sub_fat_pct: Math.round(subPct * 10) / 10,
    sub_fat_mass: Math.round(weightKg * subPct * 0.01 * 10) / 10,
    water: Math.round(waterPct * 10) / 10,
    water_mass: Math.round(weightKg * waterPct * 0.01 * 10) / 10,
    protein_mass: Math.round(proteinMass * 10) / 10,
    protein_rate: Math.round(proteinRate * 10) / 10,
    bone: Math.round(bone * 100) / 100,
    bone_rate: Math.round((bone / weightKg) * 100 * 10) / 10,
    muscle: Math.round(muscleMass * 10) / 10,
    muscle_rate: Math.round(muscleRate * 10) / 10,
    skeletal_muscle: Math.round(skeletal * 10) / 10,
    skeletal_muscle_rate: Math.round(skeletalRate * 10) / 10,
    bmr: Math.round(bmr),
    lean_mass: Math.round(leanMass * 10) / 10,
    grades: {
      visceral_fat: visceral <= 9 ? '标准' : '高',
      body_fat: fatGrade,
      fat_mass: fatGrade,
      sub_fat: band(subPct, fatLow * SUB_FAT_COEFF, fatMid * SUB_FAT_COEFF),
      bone: band(bone, ...boneRange(isMale, weightKg)),
      water: waterGrade(waterPct, isMale),
      water_mass: waterGrade(waterPct, isMale),
      protein: proteinRate < 16 ? '不足' : proteinRate > 20 ? '优秀' : '标准',
      muscle: muscleGrade,
      muscle_rate: muscleGrade,
      skeletal_muscle: band(skeletal, skeletalRef * 0.9, skeletalRef * 1.1),
      skeletal_muscle_rate: band(skeletal, skeletalRef * 0.9, skeletalRef * 1.1),
    },
  }
}
