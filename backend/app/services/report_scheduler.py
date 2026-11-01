# -*- coding: utf-8 -*-
"""月度报告自动生成调度器。

每月 1 日凌晨自动为所有用户生成上月的健康 / 财务 / 生活 / 投资 / 旅行报告。
报告与活动日志在同一次事务内落库；生成前会校验同周期报告是否已存在，
避免调度器重复执行或存在多个后端实例时产生重复报告。
"""
from __future__ import annotations

import json
import logging
from datetime import date, timedelta

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.models import (
    FinanceReport,
    FinanceTravelReport,
    HealthReport,
    InvestmentReport,
    LifestyleLifeReport,
    UserProfile,
)
from app.services import finance_report, health_report, investment_report, lifestyle_report
from app.services.activity import AUTO_ACTION, log_activity

logger = logging.getLogger("app.report_scheduler")

_scheduler: AsyncIOScheduler | None = None


def previous_month_range(ref: date | None = None) -> tuple[date, date, str]:
    """返回上一个自然月的起止日期与展示标签。

    Args:
        ref: 参考日期，默认今天。

    Returns:
        (start, end, label)，label 形如 "2026-10-01 ~ 2026-10-31"。
    """
    today = ref or date.today()
    this_month_start = today.replace(day=1)
    end = this_month_start - timedelta(days=1)
    start = end.replace(day=1)
    return start, end, f"{start.isoformat()} ~ {end.isoformat()}"


def _exists_health(db: Session, user_id: int, start: date, end: date) -> bool:
    """判断上月健康报告是否已生成。"""
    title = f"健康报告（{start.isoformat()} 至 {end.isoformat()}）"
    return db.scalar(
        select(HealthReport.id).where(
            HealthReport.user_id == user_id,
            HealthReport.report_date == end,
            HealthReport.title == title,
        )
    ) is not None


def _exists_period_report(
    db: Session,
    model,
    user_id: int,
    start: date,
    end: date,
    title: str,
) -> bool:
    """判断带明确统计周期的报告（财务 / 生活 / 投资 / 旅行）是否已生成。"""
    return db.scalar(
        select(model.id).where(
            model.user_id == user_id,
            model.period_start == start,
            model.period_end == end,
            model.title == title,
        )
    ) is not None


def _log_report(
    db: Session,
    *,
    user_id: int,
    module: str,
    report_id: int,
    summary: str,
    period: dict,
) -> None:
    """为自动生成的报告写入一条「自动」类型的活动日志。"""
    log_activity(
        db,
        user_id=user_id,
        action=AUTO_ACTION,
        module=module,
        resource_type="report",
        resource_id=report_id,
        summary=summary,
        detail={"period": period, "trigger": "monthly-scheduler"},
    )


def generate_monthly_reports(
    db: Session,
    user_id: int,
    start: date,
    end: date,
    label: str,
) -> list[dict]:
    """为单个用户生成上月尚未生成的全部报告（不提交事务）。

    Args:
        db: 数据库会话。
        user_id: 用户 ID。
        start: 上月起始日期。
        end: 上月结束日期。
        label: 周期展示标签。

    Returns:
        本次新生成的报告摘要列表，每项包含 module / report_id / title。
    """
    created: list[dict] = []

    # 健康报告
    if not _exists_health(db, user_id, start, end):
        data = health_report.build_report_data(db, start, end, user_id)
        title, summary, content = health_report.build_content_json(data)
        report = HealthReport(
            report_date=end,
            title=title,
            summary=summary,
            content=json.dumps(content, ensure_ascii=False),
            user_id=user_id,
        )
        db.add(report)
        db.flush()
        _log_report(
            db,
            user_id=user_id,
            module="health/reports",
            report_id=report.id,
            summary=f"自动生成 {label} 健康报告",
            period={"start": start.isoformat(), "end": end.isoformat()},
        )
        created.append({"module": "health/reports", "report_id": report.id, "title": title})

    # 财务报告
    finance_title = f"{label} 财务报告"
    if not _exists_period_report(
        db, FinanceReport, user_id, start, end, finance_title
    ):
        title, summary, content = finance_report.build_finance_report(
            db, start, end, label, user_id
        )
        report = FinanceReport(
            title=title,
            period_label=label,
            period_start=start,
            period_end=end,
            summary=summary,
            content=json.dumps(content, ensure_ascii=False),
            user_id=user_id,
        )
        db.add(report)
        db.flush()
        _log_report(
            db,
            user_id=user_id,
            module="finance/reports",
            report_id=report.id,
            summary=f"自动生成 {label} 财务报告",
            period={"start": start.isoformat(), "end": end.isoformat()},
        )
        created.append({"module": "finance/reports", "report_id": report.id, "title": title})

    # 生活报告
    lifestyle_title = f"{label} 生活报告"
    if not _exists_period_report(
        db, LifestyleLifeReport, user_id, start, end, lifestyle_title
    ):
        title, summary, content = lifestyle_report.build_lifestyle_report(
            db, start, end, label, user_id
        )
        report = LifestyleLifeReport(
            user_id=user_id,
            title=title,
            period_label=label,
            period_start=start,
            period_end=end,
            summary=summary,
            content=json.dumps(content, ensure_ascii=False),
        )
        db.add(report)
        db.flush()
        _log_report(
            db,
            user_id=user_id,
            module="lifestyle/reports",
            report_id=report.id,
            summary=f"自动生成 {label} 生活报告",
            period={"start": start.isoformat(), "end": end.isoformat()},
        )
        created.append({"module": "lifestyle/reports", "report_id": report.id, "title": title})

    # 投资报告
    investment_title = f"{label} 投资报告"
    if not _exists_period_report(
        db, InvestmentReport, user_id, start, end, investment_title
    ):
        title, summary, content = investment_report.build_investment_report(
            db, start, end, label, user_id
        )
        report = InvestmentReport(
            user_id=user_id,
            title=title,
            period_label=label,
            period_start=start,
            period_end=end,
            summary=summary,
            content=json.dumps(content, ensure_ascii=False),
        )
        db.add(report)
        db.flush()
        _log_report(
            db,
            user_id=user_id,
            module="investment/reports",
            report_id=report.id,
            summary=f"自动生成 {label} 投资报告",
            period={"start": start.isoformat(), "end": end.isoformat()},
        )
        created.append({"module": "investment/reports", "report_id": report.id, "title": title})

    # 旅行报告（按上月区间汇总全部行程明细）
    travel_title = f"旅行开支报告（{label}）"
    if not _exists_period_report(
        db, FinanceTravelReport, user_id, start, end, travel_title
    ):
        title, summary, content, _pstart, _pend = finance_report.build_travel_report(
            db, None, user_id, start, end
        )
        report = FinanceTravelReport(
            title=title,
            ledger_id=None,
            period_start=start,
            period_end=end,
            summary=summary,
            content=json.dumps(content, ensure_ascii=False),
            user_id=user_id,
        )
        db.add(report)
        db.flush()
        _log_report(
            db,
            user_id=user_id,
            module="finance/travel/report",
            report_id=report.id,
            summary=f"自动生成 {label} 旅行报告",
            period={"start": start.isoformat(), "end": end.isoformat()},
        )
        created.append({"module": "finance/travel/report", "report_id": report.id, "title": title})

    return created


def generate_all(
    db: Session,
    start: date | None = None,
    end: date | None = None,
    label: str | None = None,
) -> dict:
    """为全部用户生成指定周期的报告，逐用户提交并返回统计结果。

    Args:
        db: 数据库会话。
        start: 起始日期，默认上月 1 日。
        end: 结束日期，默认上月最后一天。
        label: 周期标签，默认自动生成。

    Returns:
        包含用户数、报告数量与生成明细的统计字典。
    """
    if start is None or end is None or label is None:
        start, end, label = previous_month_range()
    user_ids = db.scalars(select(UserProfile.id)).all()
    result = {"users": len(user_ids), "created": 0, "reports": []}
    for uid in user_ids:
        try:
            created = generate_monthly_reports(db, uid, start, end, label)
            db.commit()
            result["created"] += len(created)
            result["reports"].extend({"user_id": uid, **item} for item in created)
        except Exception as exc:  # noqa: BLE001 - 单用户失败不影响其他用户
            db.rollback()
            logger.exception("用户 %s 月度报告生成失败：%s", uid, exc)
            result["reports"].append({"user_id": uid, "error": str(exc)})
    return result


def _job() -> None:
    """调度任务入口：生成上月报告并写入日志。"""
    db = SessionLocal()
    try:
        start, end, label = previous_month_range()
        summary = generate_all(db, start, end, label)
        logger.info("月度报告自动生成完成：%s", summary)
    except Exception as exc:  # noqa: BLE001
        logger.exception("月度报告自动生成失败：%s", exc)
    finally:
        db.close()


def start_scheduler() -> None:
    """启动月度报告调度器（每月 1 日按配置时间执行）。"""
    global _scheduler
    if _scheduler is not None:
        return
    hour, minute = 0, 10
    try:
        h, m = settings.MONTHLY_REPORT_TIME.split(":")
        hour, minute = int(h), int(m)
    except Exception:  # noqa: BLE001 - 配置异常时沿用默认时间
        pass

    _scheduler = AsyncIOScheduler()
    _scheduler.add_job(
        _job,
        "cron",
        day=1,
        hour=hour,
        minute=minute,
        id="monthly_report_generate",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
        # 服务在 1 日当天稍晚启动时仍可补跑当天的月度报告
        misfire_grace_time=23 * 3600,
    )
    _scheduler.start()
    logger.info("月度报告调度已启动，每月 1 日 %02d:%02d 生成上月报告", hour, minute)


def stop_scheduler() -> None:
    """停止月度报告调度器。"""
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        logger.info("月度报告调度器已停止")


def is_running() -> bool:
    """返回月度报告调度器是否正在运行。"""
    return _scheduler is not None and _scheduler.running
