# -*- coding: utf-8 -*-
"""购物记录智能分类服务。

基于分类表（finance_shopping_categories）中的关键词库对商品名称进行匹配归类。
匹配规则与原 Classify 项目一致：
    1. 扫描每个分类的 keywords，记录命中数；
    2. 若分类的 exclude 关键词命中，则该分类被否决；
    3. 选择命中数最多者；数量相同按 priority 大者优先；
    4. 全部零命中，返回兜底分类（is_fallback=True）。
"""
import json
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import FinanceShoppingCategory


def _parse_json_list(raw: Optional[str]) -> list[str]:
    """解析存储为 Text 的 JSON 数组字段，异常或为空时返回空列表。"""
    if not raw:
        return []
    try:
        data = json.loads(raw)
        if isinstance(data, list):
            return [str(x) for x in data]
        return []
    except (json.JSONDecodeError, TypeError):
        return []


def classify_product(name: str, categories: list[FinanceShoppingCategory]) -> Optional[int]:
    """根据商品名称匹配分类表，返回命中的分类 id；零命中返回兜底分类 id，无兜底则返回 None。

    参数：
        name (str): 商品名称原始字符串。
        categories (list[FinanceShoppingCategory]): 当前用户的全部分类列表。
    返回值：
        Optional[int]: 命中分类的 id；零命中时返回兜底分类 id（若存在），否则 None。
    """
    if not name or not isinstance(name, str):
        name = ""
    text = name.lower()

    candidates: list[tuple[int, int, int]] = []  # (category_id, hits, priority)
    fallback_id: Optional[int] = None

    for cat in categories:
        if cat.is_fallback:
            fallback_id = cat.id
            continue
        keywords = _parse_json_list(cat.keywords)
        excludes = _parse_json_list(cat.exclude)
        if any(ex.lower() in text for ex in excludes):
            continue
        matched = [kw for kw in keywords if kw.lower() in text]
        if matched:
            candidates.append((cat.id, len(matched), cat.priority or 0))

    if not candidates:
        return fallback_id
    candidates.sort(key=lambda x: (x[1], x[2]), reverse=True)
    return candidates[0][0]


def classify_for_user(db: Session, user_id: int, product_name: str) -> Optional[int]:
    """查询指定用户的分类库并对商品名称分类，返回分类 id。

    参数：
        db (Session): 数据库会话。
        user_id (int): 用户 id。
        product_name (str): 商品名称。
    返回值：
        Optional[int]: 分类 id；无任何分类时返回 None。
    """
    categories = db.scalars(
        select(FinanceShoppingCategory).where(FinanceShoppingCategory.user_id == user_id)
    ).all()
    if not categories:
        return None
    return classify_product(product_name, categories)
