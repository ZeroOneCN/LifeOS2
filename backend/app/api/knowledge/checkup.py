"""体检组合套餐内置推荐：供不了解医学指标的用户快速选用。

参考范围为成年人常见参考区间（男女或有差异，取通用近似值），
仅供参考，实际以医院检验单为准。
"""

PANEL_PRESETS: list[dict] = [
    {
        "panel_name": "血常规",
        "note": "检查血液三系（白细胞/红细胞/血小板），筛查感染、贫血与凝血问题",
        "items": [
            {"item_name": "白细胞计数(WBC)", "unit": "×10⁹/L", "ref_low": 3.5, "ref_high": 9.5},
            {"item_name": "红细胞计数(RBC)", "unit": "×10¹²/L", "ref_low": 3.8, "ref_high": 5.8},
            {"item_name": "血红蛋白(HGB)", "unit": "g/L", "ref_low": 115, "ref_high": 175},
            {"item_name": "红细胞压积(HCT)", "unit": "%", "ref_low": 35, "ref_high": 50},
            {"item_name": "血小板计数(PLT)", "unit": "×10⁹/L", "ref_low": 125, "ref_high": 350},
            {"item_name": "中性粒细胞百分比", "unit": "%", "ref_low": 40, "ref_high": 75},
        ],
    },
    {
        "panel_name": "肝功能",
        "note": "评估肝脏代谢与损伤，常用于筛查肝病",
        "items": [
            {"item_name": "总蛋白(TP)", "unit": "g/L", "ref_low": 65, "ref_high": 85},
            {"item_name": "白蛋白(ALB)", "unit": "g/L", "ref_low": 40, "ref_high": 55},
            {"item_name": "总胆红素(TBIL)", "unit": "μmol/L", "ref_low": 3.4, "ref_high": 17.1},
            {"item_name": "谷丙转氨酶(ALT)", "unit": "U/L", "ref_low": 9, "ref_high": 50},
            {"item_name": "谷草转氨酶(AST)", "unit": "U/L", "ref_low": 15, "ref_high": 40},
            {"item_name": "碱性磷酸酶(ALP)", "unit": "U/L", "ref_low": 45, "ref_high": 125},
        ],
    },
    {
        "panel_name": "肾功能",
        "note": "评估肾脏过滤功能与代谢废物排出",
        "items": [
            {"item_name": "肌酐(Cr)", "unit": "μmol/L", "ref_low": 57, "ref_high": 97},
            {"item_name": "尿素氮(BUN)", "unit": "mmol/L", "ref_low": 3.1, "ref_high": 8.0},
            {"item_name": "尿酸(UA)", "unit": "μmol/L", "ref_low": 208, "ref_high": 428},
            {"item_name": "估算肾小球滤过率(eGFR)", "unit": "mL/min/1.73m²", "ref_low": 90, "ref_high": None},
        ],
    },
    {
        "panel_name": "血脂四项",
        "note": "评估血脂水平，评估动脉硬化/心血管风险",
        "items": [
            {"item_name": "总胆固醇(TC)", "unit": "mmol/L", "ref_low": 2.8, "ref_high": 5.2},
            {"item_name": "甘油三酯(TG)", "unit": "mmol/L", "ref_low": 0.56, "ref_high": 1.7},
            {"item_name": "高密度脂蛋白(HDL-C)", "unit": "mmol/L", "ref_low": 1.16, "ref_high": 1.55},
            {"item_name": "低密度脂蛋白(LDL-C)", "unit": "mmol/L", "ref_low": None, "ref_high": 3.4},
        ],
    },
    {
        "panel_name": "血糖检查",
        "note": "筛查糖尿病及血糖代谢异常",
        "items": [
            {"item_name": "空腹血糖(FBG)", "unit": "mmol/L", "ref_low": 3.9, "ref_high": 6.1},
            {"item_name": "糖化血红蛋白(HbA1c)", "unit": "%", "ref_low": 4, "ref_high": 6},
        ],
    },
]