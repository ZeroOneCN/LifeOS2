-- 生活中心「物品追踪」：为既有 lifestyle_items 表增加过期/使用结束/来源/购物记录关联列
-- 执行前请先备份 lifeos 库。
USE lifeos;

ALTER TABLE lifestyle_items
  ADD COLUMN expire_date DATE NULL COMMENT '过期时间' AFTER price,
  ADD COLUMN end_date DATE NULL COMMENT '使用结束日期' AFTER expire_date,
  ADD COLUMN source VARCHAR(16) NOT NULL DEFAULT 'manual' COMMENT '来源 manual/shopping' AFTER end_date,
  ADD COLUMN shopping_record_id INT NULL COMMENT '关联购物记录' AFTER source;

CREATE INDEX ix_lifestyle_items_shopping_record_id ON lifestyle_items (shopping_record_id);

-- 注：新表 lifestyle_phone_cards / lifestyle_bank_cards / lifestyle_carriers /
--     lifestyle_card_bills / lifestyle_life_reports 由后端启动时 create_all 自动创建，无需手动建表。