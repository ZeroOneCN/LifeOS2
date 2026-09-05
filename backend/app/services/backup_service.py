"""数据备份与恢复服务：导出数据为 JSON/SQL，导入 JSON，管理备份文件。"""

import json
import os
import re
import subprocess
import time
from datetime import datetime
from io import BytesIO
from pathlib import Path
from typing import Any
from zipfile import ZIP_DEFLATED, ZipFile

from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.backup import BackupLog

BACKUP_DIR = Path(__file__).resolve().parent.parent.parent / "backups"
BACKUP_DIR.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

def _serialize_value(value: Any) -> Any:
    """将 SQLAlchemy 行值转为 JSON 可序列化类型。"""
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if hasattr(value, "isoformat"):  # date, time, timedelta 等
        return str(value)
    return value


def _parse_db_url() -> dict[str, str]:
    """从 DATABASE_URL 解析 MySQL 连接参数。"""
    url = settings.DATABASE_URL
    # 格式: mysql+pymysql://user:pass@host:port/dbname
    m = re.match(
        r"mysql\+pymysql://([^:]+):([^@]+)@([^:]+):(\d+)/([^?]+)",
        url,
    )
    if not m:
        raise ValueError("DATABASE_URL 格式不支持，仅支持 mysql+pymysql 协议")
    return {
        "user": m.group(1),
        "password": m.group(2),
        "host": m.group(3),
        "port": m.group(4),
        "database": m.group(5),
    }


def _fmt_size(size_bytes: int) -> str:
    """格式化文件大小。"""
    for unit in ("B", "KB", "MB", "GB"):
        if size_bytes < 1024:
            return f"{size_bytes:.1f}{unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f}TB"


def _backup_filename(kind: str, suffix: str = ".json") -> str:
    """生成带时间戳的备份文件名。"""
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"{kind}_{ts}{suffix}"


# ---------------------------------------------------------------------------
# 核心导出 / 导入逻辑
# ---------------------------------------------------------------------------

def get_table_list(db: Session) -> list[dict[str, Any]]:
    """获取数据库所有表名及行数（仅业务表，排除系统表）。"""
    inspector = inspect(db.bind)
    all_tables = inspector.get_table_names()
    # 排除 SQLAlchemy 内部表
    skip = {"alembic_version", "spatial_ref_sys"}
    result = []
    for table in all_tables:
        if table in skip:
            continue
        count = db.scalar(text(f"SELECT COUNT(*) FROM `{table}`"))
        result.append({"name": table, "count": count or 0})
    result.sort(key=lambda r: r["name"])
    return result


def export_tables_json(
    db: Session,
    table_names: list[str] | None = None,
    compress: bool = False,
) -> tuple[bytes, str]:
    """将指定表（或全部表）导出为 JSON 格式。

    Returns:
        (bytes 数据, 建议文件名)
    """
    inspector = inspect(db.bind)
    all_tables = set(inspector.get_table_names())
    skip = {"alembic_version", "spatial_ref_sys"}
    target = (
        [t for t in table_names if t in all_tables]
        if table_names
        else [t for t in all_tables if t not in skip]
    )
    target.sort()

    export: dict[str, list[dict[str, Any]]] = {}
    for table_name in target:
        rows = db.execute(text(f"SELECT * FROM `{table_name}`")).mappings().all()
        export[table_name] = [
            {k: _serialize_value(v) for k, v in row.items()} for row in rows
        ]

    meta = {
        "exported_at": datetime.now().isoformat(),
        "database": _parse_db_url()["database"],
        "tables": target,
        "table_count": len(target),
    }
    payload = {"meta": meta, "data": export}
    raw = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")

    filename = _backup_filename("full" if table_names is None else "partial", ".json")
    if compress:
        buf = BytesIO()
        with ZipFile(buf, "w", ZIP_DEFLATED) as zf:
            zf.writestr(filename, raw)
        return buf.getvalue(), filename + ".zip"
    return raw, filename


def export_sql_mysqldump(
    table_names: list[str] | None = None,
) -> tuple[bytes, str]:
    """导出 SQL 备份。优先使用 mysqldump，不可用时用纯 Python 生成。

    Returns:
        (bytes 数据, 建议文件名)
    """
    try:
        return _export_sql_via_mysqldump(table_names)
    except (FileNotFoundError, RuntimeError) as exc:
        from app.core.database import SessionLocal

        db = SessionLocal()
        try:
            return _export_sql_pure_python(db, table_names)
        finally:
            db.close()


def _export_sql_via_mysqldump(
    table_names: list[str] | None = None,
) -> tuple[bytes, str]:
    """使用 mysqldump 导出 SQL 备份。"""
    params = _parse_db_url()
    mysqldump_cmd = settings.MYSQLDUMP_PATH or "mysqldump"
    cmd = [
        mysqldump_cmd,
        f"--user={params['user']}",
        f"--password={params['password']}",
        f"--host={params['host']}",
        f"--port={params['port']}",
        "--routines",
        "--triggers",
        "--single-transaction",
        "--default-character-set=utf8mb4",
        params["database"],
    ]
    if table_names:
        cmd.extend(table_names)

    try:
        result = subprocess.run(cmd, capture_output=True, timeout=120, check=False)
    except FileNotFoundError:
        raise RuntimeError("mysqldump 不可用，将使用纯 Python 方式生成 SQL")

    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace")[:500]
        raise RuntimeError(f"mysqldump 执行失败: {stderr}")

    sql = result.stdout
    filename = _backup_filename("sql", ".sql")
    return sql, filename


def _export_sql_pure_python(
    db: Session,
    table_names: list[str] | None = None,
) -> tuple[bytes, str]:
    """纯 Python 方式生成 SQL（不依赖 mysqldump）。"""
    from sqlalchemy import inspect, text

    inspector = inspect(db.bind)
    all_tables = set(inspector.get_table_names())
    skip = {"alembic_version", "spatial_ref_sys"}
    target = (
        [t for t in table_names if t in all_tables]
        if table_names
        else [t for t in all_tables if t not in skip]
    )
    target.sort()

    lines: list[str] = []
    lines.append(f"-- Pure Python SQL 备份")
    lines.append(f"-- 导出时间: {datetime.now().isoformat()}")
    lines.append(f"-- 数据库: {_parse_db_url()['database']}")
    lines.append("")
    lines.append("SET NAMES utf8mb4;")
    lines.append("SET FOREIGN_KEY_CHECKS = 0;")
    lines.append("")

    for table_name in target:
        # 获取建表语句
        create_stmt = db.execute(
            text(f"SHOW CREATE TABLE `{table_name}`")
        ).mappings().first()
        if not create_stmt:
            continue
        lines.append(f"-- 表: {table_name}")
        lines.append(create_stmt["Create Table"] + ";")
        lines.append("")

        # 获取数据
        rows = db.execute(text(f"SELECT * FROM `{table_name}`")).mappings().all()
        if not rows:
            continue

        columns = list(rows[0].keys())
        col_names = ", ".join(f"`{c}`" for c in columns)
        batch: list[str] = []
        for row in rows:
            vals = []
            for c in columns:
                v = row[c]
                if v is None:
                    vals.append("NULL")
                elif isinstance(v, (int, float)):
                    vals.append(str(v))
                elif isinstance(v, bool):
                    vals.append("1" if v else "0")
                elif isinstance(v, bytes):
                    vals.append(f"x'{v.hex()}'")
                else:
                    escaped = str(v).replace("'", "''").replace("\\", "\\\\")
                    vals.append(f"'{escaped}'")
            batch.append(f"({', '.join(vals)})")

        # 每500行一组 INSERT
        chunk_size = 500
        for i in range(0, len(batch), chunk_size):
            chunk = batch[i : i + chunk_size]
            lines.append(
                f"INSERT INTO `{table_name}` ({col_names}) VALUES\n"
                + ",\n".join(chunk)
                + ";"
            )
        lines.append("")

    lines.append("SET FOREIGN_KEY_CHECKS = 1;")
    lines.append("")
    lines.append("-- 备份完成")
    lines.append("")

    sql = "\n".join(lines).encode("utf-8")
    filename = _backup_filename("sql", ".sql")
    return sql, filename


def list_backup_files() -> list[dict[str, Any]]:
    """列出备份目录中的所有备份文件。"""
    if not BACKUP_DIR.exists():
        return []
    files = []
    for f in sorted(BACKUP_DIR.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True):
        if f.is_file():
            stat = f.stat()
            files.append({
                "filename": f.name,
                "size": stat.st_size,
                "size_display": _fmt_size(stat.st_size),
                "modified_at": datetime.fromtimestamp(stat.st_mtime).isoformat(),
            })
    return files


def delete_backup_file(filename: str) -> None:
    """删除指定备份文件。"""
    filepath = BACKUP_DIR / filename
    if not filepath.exists():
        raise FileNotFoundError(f"备份文件 {filename} 不存在")
    if not filepath.is_file():
        raise ValueError(f"{filename} 不是文件")
    # 安全校验：确保路径在 BACKUP_DIR 内
    resolved = filepath.resolve()
    if not str(resolved).startswith(str(BACKUP_DIR.resolve())):
        raise ValueError("不允许删除备份目录外的文件")
    filepath.unlink()


def import_json_data(
    db: Session,
    content: bytes,
    table_names: list[str] | None = None,
) -> dict[str, Any]:
    """从 JSON 备份文件导入数据。

    Args:
        db: 数据库会话
        content: JSON 字节内容
        table_names: 可选，只导入指定表

    Returns:
        导入统计信息
    """
    payload = json.loads(content.decode("utf-8"))
    data = payload.get("data", {})
    if not data:
        raise ValueError("备份文件中没有数据")

    target_tables = set(table_names) if table_names else set(data.keys())
    stats: dict[str, int] = {}
    total = 0

    for table_name, rows in data.items():
        if table_name not in target_tables:
            continue
        if not rows:
            stats[table_name] = 0
            continue

        # 获取列信息（排除自增主键或让数据库自行处理）
        inspector = inspect(db.bind)
        columns = [c["name"] for c in inspector.get_columns(table_name)]
        pk_cols = {c["name"] for c in inspector.get_pk_constraint(table_name).get(
            "constrained_columns", []
        )}

        # 逐行插入（使用原生 INSERT IGNORE 避免主键冲突）
        inserted = 0
        for row in rows:
            # 过滤：只保留表中存在的列
            filtered = {k: v for k, v in row.items() if k in columns}
            if not filtered:
                continue
            col_names = ", ".join(f"`{k}`" for k in filtered)
            placeholders = ", ".join(f":{k}" for k in filtered)
            stmt = text(
                f"INSERT IGNORE INTO `{table_name}` ({col_names}) VALUES ({placeholders})"
            )
            db.execute(stmt, filtered)
            inserted += 1

        db.commit()
        stats[table_name] = inserted
        total += inserted

    return {"tables": stats, "total_inserted": total}


def write_backup_log(
    db: Session,
    user_id: int,
    name: str,
    export_format: str,
    status: str,
    *,
    schedule_id: int | None = None,
    filename: str | None = None,
    file_size: int | None = None,
    error_message: str | None = None,
) -> BackupLog:
    """写入一条备份执行日志。"""
    from datetime import datetime

    now = datetime.now()
    log = BackupLog(
        user_id=user_id,
        schedule_id=schedule_id,
        name=name,
        export_format=export_format,
        filename=filename,
        file_size=file_size,
        status=status,
        error_message=error_message,
        started_at=now,
        finished_at=now,
    )
    db.add(log)
    db.commit()
    return log


def get_backup_logs(
    db: Session,
    user_id: int,
    page: int = 1,
    page_size: int = 20,
) -> tuple[list[dict[str, Any]], int]:
    """分页查询备份执行日志。"""
    from sqlalchemy import desc, func, select

    total = db.scalar(
        select(func.count(BackupLog.id)).where(BackupLog.user_id == user_id)
    ) or 0
    rows = db.scalars(
        select(BackupLog)
        .where(BackupLog.user_id == user_id)
        .order_by(desc(BackupLog.created_at))
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()

    def _log_to_dict(log: BackupLog) -> dict[str, Any]:
        return {
            "id": log.id,
            "schedule_id": log.schedule_id,
            "name": log.name,
            "export_format": log.export_format,
            "filename": log.filename,
            "file_size": log.file_size,
            "file_size_display": _fmt_size(log.file_size) if log.file_size else None,
            "status": log.status,
            "error_message": log.error_message,
            "started_at": log.started_at.isoformat(),
            "finished_at": log.finished_at.isoformat(),
            "created_at": log.created_at.isoformat(),
        }

    return [_log_to_dict(r) for r in rows], total