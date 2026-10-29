#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""身体成分估算（BIA 生物电阻抗分析）。

秤本身只提供体重与阻抗，体脂、水分、骨量等全部由本地公式估算。
基础公式移植自 ha-miscale2 / icomon_scale（经 ant-afu-scale 的
BodyComposition.swift 复刻），分级阈值参考以下来源：

- 体脂率分级：ha-miscale2 的分龄区间（厂商口径，非医学诊断）；
- 内脏脂肪等级：icomon_scale 的 ``BMI×0.3 − 年龄×0.05 + 0.4``，
  等级划分参考 Omron 说明书（1–9 标准，≥10 偏高）；
- 骨量 / 肌肉量区间：ha-miscale2 的按体重 / 身高分档；
- 体水分率：家用体脂秤常用区间（男 50–65%，女 45–60%）；
- 蛋白质：去脂体重 × 0.238（ant-afu-welland-scale），16–20% 为标准；
- 皮下脂肪：体脂率 × 0.71（icomon_scale）；
- 骨骼肌量：肌肉量 × 0.558（icomon_scale），参考值取 Janssen MRI
  研究（男 33 kg、女 21 kg）；
- 基础代谢：Mifflin-St Jeor 公式（1990）。

以上结果均为估算值，不能用于医学诊断。
"""

from __future__ import annotations

from typing import Any

# 阻抗无效时使用的兜底值，避免公式出现极端结果
FALLBACK_IMPEDANCE = 500.0

# 体脂率分级阈值：(性别, 年龄下限, 年龄上限) -> (偏低上限, 标准上限, 偏高水平上限)
# 低于第一项为偏低，位于区间为标准，超过第二项为偏高，超过第三项为过高
FAT_RANGES: dict[tuple[str, int, int], tuple[float, float, float]] = {
    ("male", 18, 39): (11.0, 17.0, 22.0),
    ("male", 40, 59): (12.0, 18.0, 23.0),
    ("male", 60, 200): (14.0, 20.0, 25.0),
    ("female", 18, 39): (21.0, 28.0, 35.0),
    ("female", 40, 59): (22.0, 29.0, 36.0),
    ("female", 60, 200): (23.0, 30.0, 37.0),
}

# 皮下脂肪系数（皮下脂肪率 = 体脂率 × 系数）
SUB_FAT_COEFF = 0.71
# 骨骼肌系数（骨骼肌量 = 肌肉量 × 系数）
SKELETAL_MUSCLE_COEFF = 0.558
# 蛋白质系数（蛋白质含量 = 去脂体重 × 系数）
PROTEIN_COEFF = 0.238
# 骨骼肌参考值（Janssen MRI 研究，千克）
SKELETAL_MUSCLE_REF = {"male": 33.0, "female": 21.0}


def _fat_range(is_male: bool, age: int) -> tuple[float, float, float]:
    """按性别与年龄取体脂率分级阈值。

    Args:
        is_male: 是否男性。
        age: 年龄（岁）。

    Returns:
        三元组 (偏低上限, 标准上限, 偏高水平上限)。
    """
    sex = "male" if is_male else "female"
    for (row_sex, low, high), bounds in FAT_RANGES.items():
        if row_sex != sex:
            continue
        if low <= age <= high:
            return bounds
    return FAT_RANGES[(sex, 18, 39)]


def _grade_fat(value: float, is_male: bool, age: int) -> str:
    """按体脂率阈值给出四级等级。

    Args:
        value: 体脂率（%）。
        is_male: 是否男性。
        age: 年龄（岁）。

    Returns:
        偏低 / 标准 / 偏高 / 过高。
    """
    low, mid, high = _fat_range(is_male, age)
    if value < low:
        return "偏低"
    if value < mid:
        return "标准"
    if value < high:
        return "偏高"
    return "过高"


def _bone_range(is_male: bool, weight_kg: float) -> tuple[float, float]:
    """按性别与体重取骨量标准区间（千克）。

    Args:
        is_male: 是否男性。
        weight_kg: 体重（千克）。

    Returns:
        (下限, 上限)。
    """
    if is_male:
        if weight_kg >= 75:
            return 2.0, 4.2
        if weight_kg >= 60:
            return 1.9, 4.1
        return 1.6, 3.9
    if weight_kg >= 60:
        return 1.8, 3.9
    if weight_kg >= 45:
        return 1.5, 3.8
    return 1.3, 3.6


def _muscle_range(is_male: bool, height_cm: float) -> tuple[float, float]:
    """按性别与身高取肌肉量标准区间（千克）。

    Args:
        is_male: 是否男性。
        height_cm: 身高（厘米）。

    Returns:
        (下限, 上限)。
    """
    if is_male:
        if height_cm >= 170:
            return 49.4, 59.5
        if height_cm >= 160:
            return 44.0, 52.5
        return 38.5, 46.6
    if height_cm >= 160:
        return 36.5, 42.6
    if height_cm >= 150:
        return 32.9, 37.6
    return 29.1, 34.8


def _band(value: float, low: float, high: float) -> str:
    """按标准区间给出三级等级。

    Args:
        value: 指标值。
        low: 标准下限。
        high: 标准上限。

    Returns:
        偏低 / 标准 / 偏高。
    """
    if value < low:
        return "偏低"
    if value <= high:
        return "标准"
    return "偏高"


def _water_grade(value: float, is_male: bool) -> str:
    """按体水分率区间给出三级等级。

    Args:
        value: 体水分率（%）。
        is_male: 是否男性。

    Returns:
        偏低 / 标准 / 偏高。
    """
    low, high = (50.0, 65.0) if is_male else (45.0, 60.0)
    return _band(value, low, high)


def calculate(
    weight_kg: float,
    impedance_ohm: float,
    height_cm: float,
    age: int,
    is_male: bool,
) -> dict[str, Any]:
    """根据体重、阻抗与用户资料估算身体成分。

    Args:
        weight_kg: 体重（千克）。
        impedance_ohm: 阻抗（欧姆）；小于等于 0 时按兜底值处理。
        height_cm: 身高（厘米）。
        age: 年龄（岁）。
        is_male: 是否男性。

    Returns:
        包含各项成分数值与 grades 等级的字典；输入不合法时返回空字典。
    """
    if weight_kg <= 0 or height_cm <= 0 or age <= 0:
        return {}

    height = float(height_cm)
    years = float(age)
    impedance = float(impedance_ohm) if impedance_ohm > 0 else FALLBACK_IMPEDANCE

    bmi = weight_kg / ((height / 100.0) ** 2)

    # 瘦体重系数（LBM coefficient）
    lbm = (
        (height * 9.058 / 100.0) * (height / 100.0)
        + weight_kg * 0.32
        + 12.226
        - impedance * 0.0068
        - years * 0.0542
    )

    # 体脂率
    fat_coeff = 1.0
    if is_male:
        fat_const = 0.8
        if weight_kg < 61:
            fat_coeff = 0.98
        if height > 160:
            fat_coeff *= 1.03
    else:
        fat_const = 9.25 if age <= 49 else 7.25
        if weight_kg > 60:
            fat_coeff = 0.96
        elif weight_kg < 50:
            fat_coeff = 1.02
        if height > 160:
            fat_coeff *= 1.03

    fat_pct = (1.0 - (((lbm - fat_const) * fat_coeff) / weight_kg)) * 100.0
    fat_pct = min(60.0, max(3.0, fat_pct))

    # 水分率
    water_pct = (100.0 - fat_pct) * 0.7
    water_coeff = 1.02 if water_pct <= 50 else 0.98
    water_pct = min(75.0, max(35.0, water_pct * water_coeff))

    # 骨量（千克）
    if is_male:
        bone = (0.18016894 - (lbm * 0.05158)) * -1
    else:
        bone = (0.245691014 - (lbm * 0.07158)) * -1
    bone += 0.1 if bone > 2.2 else -0.1
    bone = max(0.5, bone)

    fat_mass = fat_pct * 0.01 * weight_kg
    muscle_mass = weight_kg - fat_mass - bone * 0.85
    muscle_rate = muscle_mass / weight_kg * 100.0
    lean_mass = weight_kg - fat_mass

    # 内脏脂肪等级：icomon_scale 经验公式，限 1–50
    visceral = bmi * 0.3 - years * 0.05 + 0.4
    visceral = int(min(50.0, max(1.0, round(visceral))))

    # 皮下脂肪：占体脂率的固定比例
    sub_pct = fat_pct * SUB_FAT_COEFF

    # 蛋白质含量与占比
    protein_mass = lean_mass * PROTEIN_COEFF
    protein_rate = protein_mass / weight_kg * 100.0

    # 骨骼肌量与骨骼肌率
    skeletal = muscle_mass * SKELETAL_MUSCLE_COEFF
    skeletal_rate = skeletal / weight_kg * 100.0
    skeletal_ref = SKELETAL_MUSCLE_REF["male" if is_male else "female"]

    # 基础代谢（Mifflin-St Jeor）
    if is_male:
        bmr = 10 * weight_kg + 6.25 * height - 5 * years + 5
    else:
        bmr = 10 * weight_kg + 6.25 * height - 5 * years - 161

    fat_grade = _grade_fat(fat_pct, is_male, age)
    muscle_band = _band(muscle_mass, *_muscle_range(is_male, height))
    # 肌肉量与肌肉率使用「偏低/标准/优秀」标注
    muscle_grade = "优秀" if muscle_band == "偏高" else muscle_band
    grades = {
        "visceral_fat": "标准" if visceral <= 9 else "高",
        "body_fat": fat_grade,
        "fat_mass": fat_grade,
        "sub_fat": _band(sub_pct, _fat_range(is_male, age)[0] * SUB_FAT_COEFF,
                         _fat_range(is_male, age)[1] * SUB_FAT_COEFF),
        "bone": _band(bone, *_bone_range(is_male, weight_kg)),
        "water": _water_grade(water_pct, is_male),
        "water_mass": _water_grade(water_pct, is_male),
        "protein": "不足" if protein_rate < 16 else ("优秀" if protein_rate > 20 else "标准"),
        "muscle": muscle_grade,
        "muscle_rate": muscle_grade,
        "skeletal_muscle": _band(skeletal, skeletal_ref * 0.9, skeletal_ref * 1.1),
        "skeletal_muscle_rate": _band(skeletal, skeletal_ref * 0.9, skeletal_ref * 1.1),
    }

    return {
        "bmi": round(bmi, 1),
        "body_fat": round(fat_pct, 1),
        "fat_mass": round(fat_mass, 1),
        "visceral_fat": visceral,
        "sub_fat_pct": round(sub_pct, 1),
        "sub_fat_mass": round(weight_kg * sub_pct * 0.01, 1),
        "water": round(water_pct, 1),
        "water_mass": round(weight_kg * water_pct * 0.01, 1),
        "protein_mass": round(protein_mass, 1),
        "protein_rate": round(protein_rate, 1),
        "bone": round(bone, 2),
        "bone_rate": round(bone / weight_kg * 100.0, 1),
        "muscle": round(muscle_mass, 1),
        "muscle_rate": round(muscle_rate, 1),
        "skeletal_muscle": round(skeletal, 1),
        "skeletal_muscle_rate": round(skeletal_rate, 1),
        "bmr": round(bmr),
        "lean_mass": round(lean_mass, 1),
        "grades": grades,
    }
