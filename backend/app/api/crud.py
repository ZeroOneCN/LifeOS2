from datetime import date
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.schemas.health import PageOut


def crud_router(
    *,
    prefix: str,
    tag: str,
    model,
    create_schema: type[BaseModel],
    read_schema: type[BaseModel],
    order_by,
    date_column: str | None = None,
    stats_func: Callable[[Session, int], dict] | None = None,
) -> APIRouter:
    """根据模型与 schema 生成标准 CRUD 路由：列表(分页+日期过滤)/详情/新增/更新/删除，可选统计端点。"""

    router = APIRouter(prefix=prefix, tags=[tag])

    @router.get("", response_model=PageOut[read_schema])
    def list_items(
        page: int = Query(1, ge=1),
        page_size: int = Query(20, ge=1, le=100),
        start: date | None = None,
        end: date | None = None,
        db: Session = Depends(get_db),
    ):
        stmt = select(model)
        if date_column and (start or end):
            col = getattr(model, date_column)
            if start:
                stmt = stmt.where(col >= start)
            if end:
                stmt = stmt.where(col <= end)
        total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
        rows = db.scalars(
            stmt.order_by(order_by.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        return PageOut(items=rows, total=total, page=page, page_size=page_size)

    if stats_func:

        @router.get("/stats")
        def stats(days: int = Query(30, ge=1, le=365), db: Session = Depends(get_db)):
            return stats_func(db, days)

    @router.get("/{item_id}", response_model=read_schema)
    def get_item(item_id: int, db: Session = Depends(get_db)):
        obj = db.get(model, item_id)
        if not obj:
            raise HTTPException(status_code=404, detail="记录不存在")
        return obj

    @router.post("", response_model=read_schema, status_code=201)
    def create_item(payload: create_schema, db: Session = Depends(get_db)):
        obj = model(**payload.model_dump())
        db.add(obj)
        db.commit()
        db.refresh(obj)
        return obj

    @router.put("/{item_id}", response_model=read_schema)
    def update_item(
        item_id: int,
        payload: create_schema,
        db: Session = Depends(get_db),
    ):
        obj = db.get(model, item_id)
        if not obj:
            raise HTTPException(status_code=404, detail="记录不存在")
        for key, value in payload.model_dump().items():
            setattr(obj, key, value)
        db.commit()
        db.refresh(obj)
        return obj

    @router.delete("/{item_id}", status_code=204)
    def delete_item(item_id: int, db: Session = Depends(get_db)):
        obj = db.get(model, item_id)
        if not obj:
            raise HTTPException(status_code=404, detail="记录不存在")
        db.delete(obj)
        db.commit()
        return None

    return router
