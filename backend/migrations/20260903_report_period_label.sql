-- 报告生成支持近 7/30/90 天与自定义区间：period_label 由月度标签改为日期区间标签
-- （如 2026-09 变为 2026-08-01 ~ 2026-09-03），需扩大列宽以容纳更长标签。
-- 执行前请先备份 lifeos 库。
USE lifeos;

ALTER TABLE finance_reports
  MODIFY COLUMN period_label VARCHAR(64) NOT NULL COMMENT '周期标签，如 2026-08-01 ~ 2026-09-03';

ALTER TABLE lifestyle_life_reports
  MODIFY COLUMN period_label VARCHAR(64) NOT NULL COMMENT '周期标签，如 2026-08-01 ~ 2026-09-03';
