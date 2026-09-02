-- 财务中心「房租水电」：为既有 finance_housing 表增加 short_name 列（小区名缩写）
-- 执行前请先备份 lifeos 库。
USE lifeos;

ALTER TABLE finance_housing
  ADD COLUMN short_name VARCHAR(64) NULL COMMENT '小区名缩写' AFTER name;

-- 注：新的 finance_travel_reports 表由后端启动时 create_all 自动创建，无需手动建表。