"""修复历史财务报告里购物明细的错误内容

Revision ID: d3f6a8b1c4e2
Revises: c8a4f1d2e6b7
Create Date: 2026-11-26

旧版本生成财务报告时存在三个问题：

1. 「平台」列直接输出了 `platform_id`（如 `1`），而不是平台名称；
2. 「单价」为空时用 `0` 兜底，与总价矛盾；
3. 明细被截断为前 30 条，与摘要「购物 N 笔」口径不一致。

生成器已在 ed0ed72 / c2df869 修正，但历史报告是快照，需要按生成时刻
（`created_at`）可见的数据重建购物明细，才能和摘要笔数保持一致。
"""
import json
from typing import Any

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision = "d3f6a8b1c4e2"
down_revision = "c8a4f1d2e6b7"
branch_labels = None
depends_on = None

_SHOPPING_HEADER = ["日期", "平台", "商品", "规格", "单价", "总价"]


def _format_number(value: Any) -> str:
    """把金额格式化为最短小数形式；空值输出「—」而不是 0。"""
    if value is None:
        return "—"
    return f"{value:g}"


def _rebuild_shopping_rows(conn, user_id: int, period_start, period_end, created_at) -> list:
    """按报告生成时刻可见的购物记录重建明细行。

    只取 `created_at <= 报告生成时间` 的记录，避免把生成后才补录的订单
    混进历史快照；平台名按当前平台表映射，查不到时回落「未分类」。
    """
    platform_rows = conn.execute(
        text(
            "SELECT id, name FROM finance_shopping_platforms "
            "WHERE user_id = :user_id"
        ),
        {"user_id": user_id},
    ).all()
    platform_names = {row[0]: row[1] for row in platform_rows}

    records = conn.execute(
        text(
            "SELECT record_date, platform_id, product_name, spec, "
            "unit_price, total_price FROM finance_shopping_records "
            "WHERE user_id = :user_id AND record_date >= :start "
            "AND record_date <= :end AND created_at <= :created_at "
            "ORDER BY record_date, id"
        ),
        {
            "user_id": user_id,
            "start": period_start,
            "end": period_end,
            "created_at": created_at,
        },
    ).all()

    rows = []
    for record in records:
        record_date, platform_id, product_name, spec, unit_price, total_price = record
        rows.append(
            [
                record_date.isoformat() if hasattr(record_date, "isoformat") else str(record_date)[:10],
                platform_names.get(platform_id, "未分类"),
                product_name,
                spec or "—",
                _format_number(unit_price),
                _format_number(total_price),
            ]
        )
    return rows


def upgrade() -> None:
    """重写历史财务报告的购物明细表，修正平台名、单价与截断行数。"""
    conn = op.get_bind()
    reports = conn.execute(
        text(
            "SELECT id, user_id, period_start, period_end, created_at, content "
            "FROM finance_reports"
        )
    ).all()
    for report in reports:
        report_id, user_id, period_start, period_end, created_at, raw_content = report
        if not raw_content:
            continue
        try:
            content = json.loads(raw_content)
        except (TypeError, ValueError):
            continue
        if not isinstance(content, list):
            continue

        rows = _rebuild_shopping_rows(
            conn, user_id, period_start, period_end, created_at
        )
        changed = False
        for index, block in enumerate(content):
            if not isinstance(block, dict) or block.get("type") != "table":
                continue
            if block.get("header") != _SHOPPING_HEADER:
                continue
            block["rows"] = rows
            changed = True
            # 同步章节标题的笔数，保持与明细行数一致
            if index > 0 and isinstance(content[index - 1], dict):
                heading = content[index - 1]
                if heading.get("type") == "h2" and "购物明细" in str(heading.get("text", "")):
                    heading["text"] = f"四、购物明细（共 {len(rows)} 笔）"
            break

        if changed:
            conn.execute(
                text("UPDATE finance_reports SET content = :content WHERE id = :id"),
                {
                    "content": json.dumps(content, ensure_ascii=False),
                    "id": report_id,
                },
            )


def downgrade() -> None:
    """数据修复不回滚：旧内容本身是错误的。"""
    pass
