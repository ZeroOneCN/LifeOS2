"""数据备份与恢复路由：导出/导入/管理备份文件。"""

import json

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import UserProfile
from app.models.backup import ScheduledBackup
from app.services import backup_service
from app.services.backup_scheduler import reload_schedules

router = APIRouter(prefix="/backup", tags=["backup"])


# ── 请求/响应模型 ──────────────────────────────────────────────────────────

class ExportReq(BaseModel):
    tables: list[str] | None = None  # 空 = 全部表
    format: str = "json"  # json | sql
    compress: bool = False


class ImportReq(BaseModel):
    tables: list[str] | None = None  # 空 = 导入全部表


class TableInfo(BaseModel):
    name: str
    count: int


class BackupFileInfo(BaseModel):
    filename: str
    size: int
    size_display: str
    modified_at: str


# ── 定时备份模型 ──────────────────────────────────────────────────────────

class ScheduleCreate(BaseModel):
    name: str
    cron_expression: str  # 5-field cron, e.g. "0 3 * * *"
    export_format: str = "json"
    compress: bool = False
    table_selection: str = "all"
    selected_tables: list[str] | None = None


class ScheduleUpdate(BaseModel):
    name: str | None = None
    cron_expression: str | None = None
    export_format: str | None = None
    compress: bool | None = None
    table_selection: str | None = None
    selected_tables: list[str] | None = None
    enabled: bool | None = None


class ScheduleRead(BaseModel):
    id: int
    name: str
    enabled: bool
    cron_expression: str
    export_format: str
    compress: bool
    table_selection: str
    selected_tables: list[str] | None = None
    last_run_at: str | None = None
    last_status: str | None = None
    created_at: str
    updated_at: str


# ── 接口 ──────────────────────────────────────────────────────────────────

@router.get("/tables", response_model=list[TableInfo])
def list_tables(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """获取所有数据表及其记录数。"""
    return backup_service.get_table_list(db)


@router.post("/export")
def export_data(
    payload: ExportReq,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """导出数据为 JSON 或 SQL 格式。"""
    try:
        if payload.format == "sql":
            data, filename = backup_service.export_sql_mysqldump(payload.tables)
        else:
            data, filename = backup_service.export_tables_json(
                db, payload.tables, payload.compress
            )
        # 写入执行日志
        filepath = backup_service.BACKUP_DIR / filename
        backup_service.write_backup_log(
            db, user.id, "手动导出", payload.format, "success",
            filename=filename, file_size=filepath.stat().st_size if filepath.exists() else None,
        )
    except RuntimeError as e:
        backup_service.write_backup_log(
            db, user.id, "手动导出", payload.format, "failed",
            error_message=str(e)[:2000],
        )
        raise HTTPException(status_code=500, detail=str(e))

    media_type = (
        "application/zip" if filename.endswith(".zip")
        else "application/sql" if filename.endswith(".sql")
        else "application/json"
    )
    return Response(content=data, media_type=media_type, headers={
        "Content-Disposition": f'attachment; filename="{filename}"',
    })


@router.get("/exports", response_model=list[BackupFileInfo])
def list_backups(
    user: UserProfile = Depends(get_current_user),
):
    """列出所有已生成的备份文件。"""
    return backup_service.list_backup_files()


@router.get("/exports/{filename}")
def download_backup(
    filename: str,
    user: UserProfile = Depends(get_current_user),
):
    """下载指定的备份文件。"""
    filepath = backup_service.BACKUP_DIR / filename
    if not filepath.exists() or not filepath.is_file():
        raise HTTPException(status_code=404, detail="备份文件不存在")
    data = filepath.read_bytes()
    # 根据扩展名推断 media_type
    ext = filepath.suffix.lower()
    media_type = {
        ".json": "application/json",
        ".sql": "application/sql",
        ".zip": "application/zip",
    }.get(ext, "application/octet-stream")
    return Response(content=data, media_type=media_type, headers={
        "Content-Disposition": f'attachment; filename="{filename}"',
    })


@router.delete("/exports/{filename}")
def delete_backup(
    filename: str,
    user: UserProfile = Depends(get_current_user),
):
    """删除指定的备份文件。"""
    try:
        backup_service.delete_backup_file(filename)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="备份文件不存在")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"message": f"备份文件 {filename} 已删除"}


@router.post("/import")
def import_data(
    file: UploadFile,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """上传 JSON 备份文件并导入数据。"""
    if not file.filename or not file.filename.endswith(".json"):
        raise HTTPException(status_code=400, detail="仅支持 .json 格式的备份文件导入")

    content = file.file.read()
    try:
        result = backup_service.import_json_data(db, content)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"导入失败: {e}")

    return {
        "message": "导入完成",
        "total_inserted": result["total_inserted"],
        "tables": result["tables"],
    }


# ── 定时备份 CRUD ────────────────────────────────────────────────────────


@router.get("/schedules", response_model=list[ScheduleRead])
def list_schedules(
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """列出当前用户的定时备份任务。"""
    rows = db.scalars(
        select(ScheduledBackup)
        .where(ScheduledBackup.user_id == user.id)
        .order_by(ScheduledBackup.created_at.desc())
    ).all()
    return [_schedule_to_read(s) for s in rows]


@router.post("/schedules", response_model=ScheduleRead)
def create_schedule(
    payload: ScheduleCreate,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """创建定时备份任务。"""
    s = ScheduledBackup(
        user_id=user.id,
        name=payload.name,
        cron_expression=payload.cron_expression,
        export_format=payload.export_format,
        compress=payload.compress,
        table_selection=payload.table_selection,
        selected_tables=json.dumps(payload.selected_tables) if payload.selected_tables else None,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    reload_schedules()
    return _schedule_to_read(s)


@router.put("/schedules/{schedule_id}", response_model=ScheduleRead)
def update_schedule(
    schedule_id: int,
    payload: ScheduleUpdate,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """更新定时备份任务。"""
    s = db.scalar(
        select(ScheduledBackup).where(
            ScheduledBackup.id == schedule_id,
            ScheduledBackup.user_id == user.id,
        )
    )
    if not s:
        raise HTTPException(status_code=404, detail="定时备份任务不存在")

    update_data = payload.model_dump(exclude_unset=True)
    if "selected_tables" in update_data:
        update_data["selected_tables"] = (
            json.dumps(update_data["selected_tables"])
            if update_data["selected_tables"] is not None
            else None
        )
    for key, value in update_data.items():
        setattr(s, key, value)
    db.commit()
    db.refresh(s)
    reload_schedules()
    return _schedule_to_read(s)


@router.delete("/schedules/{schedule_id}")
def delete_schedule(
    schedule_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """删除定时备份任务。"""
    s = db.scalar(
        select(ScheduledBackup).where(
            ScheduledBackup.id == schedule_id,
            ScheduledBackup.user_id == user.id,
        )
    )
    if not s:
        raise HTTPException(status_code=404, detail="定时备份任务不存在")
    db.delete(s)
    db.commit()
    reload_schedules()
    return {"message": "定时备份任务已删除"}


@router.post("/schedules/{schedule_id}/toggle", response_model=ScheduleRead)
def toggle_schedule(
    schedule_id: int,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """启用/禁用定时备份任务。"""
    s = db.scalar(
        select(ScheduledBackup).where(
            ScheduledBackup.id == schedule_id,
            ScheduledBackup.user_id == user.id,
        )
    )
    if not s:
        raise HTTPException(status_code=404, detail="定时备份任务不存在")
    s.enabled = not s.enabled
    db.commit()
    db.refresh(s)
    reload_schedules()
    return _schedule_to_read(s)


def _schedule_to_read(s: ScheduledBackup) -> ScheduleRead:
    return ScheduleRead(
        id=s.id,
        name=s.name,
        enabled=s.enabled,
        cron_expression=s.cron_expression,
        export_format=s.export_format,
        compress=s.compress,
        table_selection=s.table_selection,
        selected_tables=json.loads(s.selected_tables) if s.selected_tables else None,
        last_run_at=s.last_run_at.isoformat() if s.last_run_at else None,
        last_status=s.last_status,
        created_at=s.created_at.isoformat(),
        updated_at=s.updated_at.isoformat(),
    )


# ── 备份日志 ──────────────────────────────────────────────────────────────


class LogRead(BaseModel):
    id: int
    schedule_id: int | None = None
    name: str
    export_format: str
    filename: str | None = None
    file_size: int | None = None
    file_size_display: str | None = None
    status: str
    error_message: str | None = None
    started_at: str
    finished_at: str
    created_at: str


class LogPage(BaseModel):
    items: list[LogRead]
    total: int
    page: int
    page_size: int


@router.get("/logs", response_model=LogPage)
def list_logs(
    page: int = 1,
    page_size: int = 20,
    db: Session = Depends(get_db),
    user: UserProfile = Depends(get_current_user),
):
    """分页查询备份执行日志。"""
    items, total = backup_service.get_backup_logs(db, user.id, page, page_size)
    return {"items": items, "total": total, "page": page, "page_size": page_size}