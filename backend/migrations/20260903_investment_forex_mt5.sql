-- 投资中心「外汇交易」：将 investment_forex 表重构为 MT5 导入格式
-- 新增资金动态表 investment_fund_records 与投资报告表 investment_reports 由后端启动时 create_all 自动创建。
-- ⚠️ 执行前请先停止后端服务，并备份 lifeos 库（例如 mysqldump -u root -p lifeos > backups/lifeos_<时间戳>.sql）。
USE lifeos;

-- 1) 重命名旧列到新字段
ALTER TABLE investment_forex
  CHANGE COLUMN pair symbol VARCHAR(24) NOT NULL COMMENT '交易品种',
  CHANGE COLUMN direction order_type VARCHAR(8) NOT NULL COMMENT '订单类型 buy/sell';

-- 2) 新增 MT5 字段
ALTER TABLE investment_forex
  ADD COLUMN commission DOUBLE NOT NULL DEFAULT 0 COMMENT '手续费' AFTER lot_size,
  ADD COLUMN overnight_fee DOUBLE NOT NULL DEFAULT 0 COMMENT '隔夜费' AFTER pnl,
  ADD COLUMN open_time DATETIME NULL COMMENT '开仓时间' AFTER overnight_fee,
  ADD COLUMN close_time DATETIME NULL COMMENT '平仓时间' AFTER open_time,
  ADD COLUMN holding INT NULL COMMENT '持仓时间(分钟)' AFTER close_time;

-- 3) 既有数据兜底：用 trade_date 初始化开平仓时间与持仓
UPDATE investment_forex
SET open_time  = CAST(CONCAT(trade_date, ' 00:00:00') AS DATETIME),
    close_time = CAST(CONCAT(trade_date, ' 00:00:00') AS DATETIME),
    holding    = 0
WHERE open_time IS NULL OR close_time IS NULL;