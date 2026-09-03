from datetime import date, timedelta
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func, select
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
    date_column: str | None = None,
    stats_func: Callable[[Session, int, int], dict] | None = None,
    extra_routes: Callable[[APIRouter], None] | None = None,
) -> APIRouter:
    """根据模型与 schema 生成标准 CRUD 路由：列表(分页+日期过滤)/详情/新增/更新/删除，可选统计端点。

    所有业务模型（含 user_id）均按当前登录用户隔离：读/改/删仅限本人记录，新增自动归属当前用户。
    stats_func 签名：`(db, days, user_id)`。
    extra_routes: 在动态路由 /{item_id} 之前注册的固定路由，其内部触库端点需自行依赖 get_current_user 并过滤。
    """

    router = APIRouter(prefix=prefix, tags=[tag])
    user_owned = hasattr(model, "user_id")

    @router.get("", response_model=PageOut[read_schema])
    def list_items(
        page: int = Query(1, ge=1),
        page_size: int = Query(20, ge=1, le=100),
        start: date | None = None,
        end: date | None = None,
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
        total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
        sort_cols = order_by if isinstance(order_by, (list, tuple)) else [order_by]
        rows = db.scalars(
            stmt.order_by(*[c.desc() for c in sort_cols])
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
        for key, value in payload.model_dump().items():
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