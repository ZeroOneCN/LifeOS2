from datetime import date, timedelta
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import UserProfile
from app.schemas.health import PageOut


def _owned_get(db: Session, model, item_id: int, user_id: int):
    """按 id + user_id 归属查询，不存在或非本人返回 None。"""
    return db.scalars(
        select(model).where(model.id == item_id, model.user_id == user_id)
    ).first()


def _raise_if_conflict(
    db: Session,
    model,
    user_id: int,
    conflict_fields: list[str],
    payload: BaseModel,
    obj=None,
    exclude_id: int | None = None,
    conflict_msg: str | None = None,
) -> None:
    """业务唯一性校验：同用户下是否存在与 payload 指定冲突字段值相同的记录。

    新增时对照 payload 全部冲突字段；更新时仅对照 payload 实际传入的字段并排除自身，
    命中则抛 409。obj 用于新增场景读取默认值（字段未传时按模型默认值参与判断）。
    """
    data = payload.model_dump(exclude_unset=True)
    conds = []
    for f in conflict_fields:
        if f in data:
            conds.append(getattr(model, f) == data[f])
        elif obj is not None and getattr(obj, f) is not None:
            conds.append(getattr(model, f) == getattr(obj, f))
    if not conds:
        return
    stmt = select(model).where(model.user_id == user_id, *conds)
    if exclude_id is not None:
        stmt = stmt.where(model.id != exclude_id)
    dup = db.scalar(stmt)
    if dup is not None:
        raise HTTPException(
            status_code=409,
            detail=conflict_msg or "已存在相同记录",
        )


def days_since(days: int):
    """days>=1 返回近 N 天起始日；days<=0 返回 None（不过滤，即全部）。"""
    return (date.today() - timedelta(days=days - 1)) if days and days > 0 else None


def crud_router(
    *,
    prefix: str,
    tag: str,
    model,
    create_schema: type[BaseModel],
    read_schema: type[BaseModel],
    order_by,
    order_dir: str = "desc",
    date_column: str | None = None,
    stats_func: Callable[[Session, int, int], dict] | None = None,
    extra_routes: Callable[[APIRouter], None] | None = None,
    search_columns: list[str] | None = None,
    conflict_fields: list[str] | None = None,
    conflict_msg: str | None = None,
) -> APIRouter:
    """根据模型与 schema 生成标准 CRUD 路由：列表(分页+日期过滤)/详情/新增/更新/删除，可选统计端点。

    所有业务模型（含 user_id）均按当前登录用户隔离：读/改/删仅限本人记录，新增自动归属当前用户。
    stats_func 签名：`(db, days, user_id)`。
    extra_routes: 在动态路由 /{item_id} 之前注册的固定路由，其内部触库端点需自行依赖 get_current_user 并过滤。
    conflict_fields: 业务唯一性字段。新增时若同用户已存在相同字段值的记录则返回 409；
    更新时排除自身（防止编辑未改值时报冲突）。conflict_msg 为冲突提示文案。
    """

    router = APIRouter(prefix=prefix, tags=[tag])
    user_owned = hasattr(model, "user_id")

    @router.get("", response_model=PageOut[read_schema])
    def list_items(
        page: int = Query(1, ge=1),
        page_size: int = Query(20, ge=1, le=100),
        start: date | None = None,
        end: date | None = None,
        search_text: str | None = None,
        db: Session = Depends(get_db),
        current_user: UserProfile = Depends(get_current_user),
    ):
        stmt = select(model)
        if user_owned:
            stmt = stmt.where(model.user_id == current_user.id)
        if date_column and (start or end):
            col = getattr(model, date_column)
            if start:
                stmt = stmt.where(col >= start)
            if end:
                stmt = stmt.where(col <= end)
        if search_columns and search_text and search_text.strip():
            kw = f"%{search_text.strip()}%"
            stmt = stmt.where(
                or_(
                    *[getattr(model, c).ilike(kw) for c in search_columns]
                )
            )
        total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
        sort_cols = order_by if isinstance(order_by, (list, tuple)) else [order_by]
        order_clauses = [c if order_dir == "asc" else c.desc() for c in sort_cols]
        rows = db.scalars(
            stmt.order_by(*order_clauses)
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        return PageOut(items=rows, total=total, page=page, page_size=page_size)

    if stats_func:

        @router.get("/stats")
        def stats(
            days: int = Query(30, ge=0, le=365),
            db: Session = Depends(get_db),
            current_user: UserProfile = Depends(get_current_user),
        ):
            return stats_func(db, days, current_user.id)

    # 固定静态路由（/estimate、/settings 等）必须在 /{item_id} 之前注册
    if extra_routes:
        extra_routes(router)

    @router.get("/{item_id}", response_model=read_schema)
    def get_item(
        item_id: int,
        db: Session = Depends(get_db),
        current_user: UserProfile = Depends(get_current_user),
    ):
        obj = (
            _owned_get(db, model, item_id, current_user.id)
            if user_owned
            else db.get(model, item_id)
        )
        if not obj:
            raise HTTPException(status_code=404, detail="记录不存在")
        return obj

    @router.post("", response_model=read_schema, status_code=201)
    def create_item(
        payload: create_schema,
        db: Session = Depends(get_db),
        current_user: UserProfile = Depends(get_current_user),
    ):
        obj = model(**payload.model_dump())
        if user_owned:
            obj.user_id = current_user.id
        if conflict_fields and user_owned:
            _raise_if_conflict(
                db, model, current_user.id, conflict_fields, payload, obj,
                conflict_msg=conflict_msg,
            )
        db.add(obj)
        db.commit()
        db.refresh(obj)
        return obj

    @router.put("/{item_id}", response_model=read_schema)
    def update_item(
        item_id: int,
        payload: create_schema,
        db: Session = Depends(get_db),
        current_user: UserProfile = Depends(get_current_user),
    ):
        obj = (
            _owned_get(db, model, item_id, current_user.id)
            if user_owned
            else db.get(model, item_id)
        )
        if not obj:
            raise HTTPException(status_code=404, detail="记录不存在")
        if conflict_fields and user_owned:
            _raise_if_conflict(
                db,
                model,
                current_user.id,
                conflict_fields,
                payload,
                obj,
                exclude_id=item_id,
                conflict_msg=conflict_msg,
            )
        for key, value in payload.model_dump(exclude_unset=True).items():
            setattr(obj, key, value)
        db.commit()
        db.refresh(obj)
        return obj

    @router.delete("/{item_id}", status_code=204)
    def delete_item(
        item_id: int,
        db: Session = Depends(get_db),
        current_user: UserProfile = Depends(get_current_user),
    ):
        obj = (
            _owned_get(db, model, item_id, current_user.id)
            if user_owned
            else db.get(model, item_id)
        )
        if not obj:
            raise HTTPException(status_code=404, detail="记录不存在")
        db.delete(obj)
        db.commit()
        return None

    return router