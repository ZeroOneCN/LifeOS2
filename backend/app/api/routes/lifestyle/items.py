from collections import defaultdict
from datetime import date

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.crud import crud_router
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import FinanceShoppingRecord, LifestyleItem, UserProfile
from app.schemas.lifestyle import ItemCreate, ItemRead

router = APIRouter()


def _usage_days(item: LifestyleItem) -> int:
    """已使用天数：从购买日到使用结束日（或今天）。"""
    purchase = item.purchase_date
    if not purchase:
        return 0
    end = item.end_date or date.today()
    if end < purchase:
        end = purchase
    return max(0, (end - purchase).days)


def _item_stats(db: Session, days: int, user_id: int) -> dict:
    rows = db.scalars(
        select(LifestyleItem).where(LifestyleItem.user_id == user_id)
    ).all()

    by_category: dict[str, int] = defaultdict(int)
    by_status: dict[str, int] = defaultdict(int)
    by_source: dict[str, int] = defaultdict(int)

    total_value = 0.0
    used_avg_daily = 0.0
    costed_usage = 0
    expiring = 0
    expired = 0
    today = date.today()
    for r in rows:
        by_category[r.category] += 1
        by_status[r.status] += 1
        by_source[r.source] += 1
        total_value += r.price or 0
        if r.expire_date:
            left = (r.expire_date - today).days
            if left < 0:
                expired += 1
            elif days > 0 and left <= days:
                expiring += 1
        u = _usage_days(r)
        if (r.price or 0) > 0 and u > 0:
            used_avg_daily += r.price / u
            costed_usage += 1

    by_category_items = [
        {"category": c, "count": n}
        for c, n in sorted(by_category.items(), key=lambda x: -x[1])
    ]
    by_status_items = [
        {"status": s, "count": n}
        for s, n in sorted(by_status.items(), key=lambda x: -x[1])
    ]
    by_source_items = [
        {"source": s, "count": n}
        for s, n in sorted(by_source.items(), key=lambda x: -x[1])
    ]

    return {
        "total": len(rows),
        "in_use": sum(1 for r in rows if r.status == "in_use"),
        "total_value": round(total_value, 2),
        "total_usage_days": sum(_usage_days(r) for r in rows),
        "avg_daily_cost": round(used_avg_daily / costed_usage, 2) if costed_usage else 0,
        "expiring": expiring,
        "expired": expired,
        "by_category": by_category_items,
        "by_status": by_status_items,
        "by_source": by_source_items,
    }


class SyncReq(BaseModel):
    # 为空列表时表示同步当前用户全部未同步的购物记录
    record_ids: list[int] = []


def _sync_candidates(db: Session, user_id: int) -> list[dict]:
    """返回当前用户尚未同步为物品的全部购物记录（按日期倒序）。"""
    existing = set(
        db.scalars(
            select(LifestyleItem.shopping_record_id).where(
                LifestyleItem.user_id == user_id,
                LifestyleItem.source == "shopping",
                LifestyleItem.shopping_record_id.is_not(None),
            )
        ).all()
    )
    records = db.scalars(
        select(FinanceShoppingRecord)
        .where(FinanceShoppingRecord.user_id == user_id)
        .order_by(FinanceShoppingRecord.record_date.desc())
    ).all()
    out = []
    for r in records:
        if r.id in existing:
            continue
        out.append(
            {
                "id": r.id,
                "record_date": r.record_date.isoformat() if r.record_date else None,
                "product_name": r.product_name,
                "spec": r.spec,
                "total_price": r.total_price,
            }
        )
    return out


def _items_extra(api_router: APIRouter):
    @api_router.get("/sync-candidates")
    def sync_candidates(
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        return _sync_candidates(db, user.id)

    @api_router.post("/sync")
    def sync_from_shopping(
        payload: SyncReq,
        db: Session = Depends(get_db),
        user: UserProfile = Depends(get_current_user),
    ):
        # 未指定 record_ids 时，自动同步当前用户全部尚未同步为物品的购物记录
        if not payload.record_ids:
            candidates = _sync_candidates(db, user.id)
            created = 0
            for c in candidates:
                purchase = None
                if c.get("record_date"):
                    try:
                        purchase = date.fromisoformat(c["record_date"])
                    except ValueError:
                        purchase = None
                db.add(
                    LifestyleItem(
                        item_name=c["product_name"],
                        category="购物",
                        status="in_use",
                        purchase_date=purchase,
                        price=c.get("total_price"),
                        source="shopping",
                        shopping_record_id=c["id"],
                        user_id=user.id,
                        note=f"来自购物记录（{c['product_name']}{' · ' + c['spec'] if c.get('spec') else ''}）",
                    )
                )
                created += 1
            db.commit()
            return {"created": created, "skipped": 0}

        records = db.scalars(
            select(FinanceShoppingRecord).where(
                FinanceShoppingRecord.user_id == user.id,
                FinanceShoppingRecord.id.in_(payload.record_ids),
            )
        ).all()
        existing = set(
            db.scalars(
                select(LifestyleItem.shopping_record_id).where(
                    LifestyleItem.user_id == user.id,
                    LifestyleItem.source == "shopping",
                    LifestyleItem.shopping_record_id.is_not(None),
                )
            ).all()
        )
        created = 0
        for r in records:
            if r.id in existing:
                continue
            db.add(
                LifestyleItem(
                    item_name=r.product_name,
                    category="购物",
                    status="in_use",
                    purchase_date=r.record_date,
                    price=r.total_price,
                    source="shopping",
                    shopping_record_id=r.id,
                    user_id=user.id,
                    note=f"来自购物记录（{r.product_name}{' · ' + r.spec if r.spec else ''}）",
                )
            )
            created += 1
        db.commit()
        return {"created": created, "skipped": len(records) - created}


router = crud_router(
    prefix="/lifestyle/items",
    tag="lifestyle-items",
    model=LifestyleItem,
    create_schema=ItemCreate,
    read_schema=ItemRead,
    order_by=LifestyleItem.id,
    stats_func=_item_stats,
    extra_routes=_items_extra,
)