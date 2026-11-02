"""通用 CRUD 工具测试：日期回溯口径与批量 PATCH 字段白名单。"""

from datetime import date, timedelta

import pytest

from app.api.crud import _allowed_patch_fields, days_since
from app.models import FinanceUtility, HealthSteps


def test_days_since_positive():
    """days>=1 表示含今天在内的近 N 天，起点为今天-(N-1)。"""
    assert days_since(30) == date.today() - timedelta(days=29)
    assert days_since(1) == date.today()


@pytest.mark.parametrize("days", [0, -1, -7])
def test_days_since_non_positive_returns_none(days):
    """days<=0 表示不过滤（返回 None），避免出现非法起始日。"""
    assert days_since(days) is None


def test_allowed_patch_fields_excludes_protected():
    """批量 PATCH 白名单必须排除主键、归属用户与审计时间戳。"""
    allowed = _allowed_patch_fields(FinanceUtility)
    assert {"id", "user_id", "created_at", "updated_at"}.isdisjoint(allowed)


def test_allowed_patch_fields_includes_business_columns():
    """业务字段仍应可批量修改，保证现有前端批量操作不受影响。"""
    allowed = _allowed_patch_fields(FinanceUtility)
    assert {"amount", "paid", "fee_type", "bill_month"}.issubset(allowed)


def test_allowed_patch_fields_health_steps():
    """白名单按模型列动态生成，对健康步数同样成立。"""
    allowed = _allowed_patch_fields(HealthSteps)
    assert "steps" in allowed
    assert "user_id" not in allowed
    assert "id" not in allowed
