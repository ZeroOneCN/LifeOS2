-- 财务中心升级：网贷利息/还款优惠/订阅扩展字段 + 订阅分类表
USE lifeos;

-- 1. 网贷账单：新增利息列
ALTER TABLE finance_loan_bills
  ADD COLUMN interest FLOAT NULL DEFAULT 0 COMMENT '其中利息部分' AFTER amount;

-- 2. 还款记录：新增优惠列
ALTER TABLE finance_repayments
  ADD COLUMN discount FLOAT NULL DEFAULT 0 COMMENT '优惠金额（券/抵扣）' AFTER amount;

-- 3. 服务订阅：新增方案/到期/自动续费
ALTER TABLE finance_subscriptions
  ADD COLUMN plan_name VARCHAR(128) NULL COMMENT '方案名称' AFTER name,
  ADD COLUMN end_date DATE NULL COMMENT '到期时间' AFTER start_date,
  ADD COLUMN auto_renew TINYINT(1) NOT NULL DEFAULT 0 COMMENT '自动续费' AFTER end_date;

-- 4. 订阅分类表
CREATE TABLE IF NOT EXISTS finance_subscription_categories (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(32) NOT NULL,
  index ix_fsc_name (name),
  user_id INT NOT NULL,
  created_at DATETIME,
  updated_at DATETIME
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订阅分类';

-- 5. 分类种子（来自 subscription-categories.csv）
INSERT IGNORE INTO finance_subscription_categories (name, user_id, created_at, updated_at)
SELECT name, 1, NOW(), NOW() FROM (
  SELECT 'AI工具' AS name UNION SELECT '影视会员' UNION SELECT '服务器'
) t
WHERE NOT EXISTS (SELECT 1 FROM finance_subscription_categories c WHERE c.name = t.name AND c.user_id = 1);