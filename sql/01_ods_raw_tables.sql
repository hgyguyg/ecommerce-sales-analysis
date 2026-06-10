-- ============================================================
-- 电商销售数据分析 — ODS 层：原始数据入库
-- 仓库: ecommerce-sales-analysis
-- 数据源: 某电商平台 2 年订单数据，约 12 万条
-- ============================================================

-- 创建数据库
CREATE DATABASE IF NOT EXISTS ecommerce_sales
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE ecommerce_sales;

-- ============================================================
-- ODS 层: 订单原始表（从 CSV 导入的原始数据）
-- ============================================================
DROP TABLE IF EXISTS ods_orders_raw;
CREATE TABLE ods_orders_raw (
    order_id        VARCHAR(32)   NOT NULL COMMENT '订单ID',
    product_name    VARCHAR(200)  DEFAULT NULL COMMENT '商品名称',
    category        VARCHAR(100)  DEFAULT NULL COMMENT '商品类目',
    sub_category    VARCHAR(100)  DEFAULT NULL COMMENT '商品子类目',
    unit_price      DECIMAL(10,2) DEFAULT NULL COMMENT '单价',
    quantity        INT           DEFAULT NULL COMMENT '购买数量',
    total_amount    DECIMAL(12,2) DEFAULT NULL COMMENT '订单总金额',
    discount_rate   DECIMAL(4,2)  DEFAULT NULL COMMENT '折扣率',
    payment_method  VARCHAR(20)   DEFAULT NULL COMMENT '支付方式',
    order_status    VARCHAR(20)   DEFAULT NULL COMMENT '订单状态(pending/paid/shipped/cancelled/returned)',
    customer_id     VARCHAR(32)   DEFAULT NULL COMMENT '客户ID',
    customer_region VARCHAR(50)   DEFAULT NULL COMMENT '客户所在区域',
    order_date      VARCHAR(20)   DEFAULT NULL COMMENT '下单日期(原始)',
    ship_date       VARCHAR(20)   DEFAULT NULL COMMENT '发货日期(原始)',
    promotion_id    VARCHAR(32)   DEFAULT NULL COMMENT '促销活动ID',
    etl_time        DATETIME      DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL加载时间',
    PRIMARY KEY (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='ODS-订单原始表';

-- ============================================================
-- ODS 层: 客户信息原始表
-- ============================================================
DROP TABLE IF EXISTS ods_customers_raw;
CREATE TABLE ods_customers_raw (
    customer_id     VARCHAR(32)  NOT NULL COMMENT '客户ID',
    customer_name   VARCHAR(100) DEFAULT NULL COMMENT '客户名称(脱敏)',
    segment         VARCHAR(20)  DEFAULT NULL COMMENT '客户分层(consumer/corporate/home_office)',
    city            VARCHAR(50)  DEFAULT NULL COMMENT '城市',
    region          VARCHAR(20)  DEFAULT NULL COMMENT '大区(华东/华南/华北/华中/西南/西北)',
    register_date   VARCHAR(20)  DEFAULT NULL COMMENT '注册日期(原始)',
    etl_time        DATETIME     DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL加载时间',
    PRIMARY KEY (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='ODS-客户信息原始表';

-- ============================================================
-- ODS 层: 促销活动原始表
-- ============================================================
DROP TABLE IF EXISTS ods_promotions_raw;
CREATE TABLE ods_promotions_raw (
    promotion_id    VARCHAR(32)   NOT NULL COMMENT '促销活动ID',
    promotion_name  VARCHAR(200)  DEFAULT NULL COMMENT '活动名称',
    promotion_type  VARCHAR(30)   DEFAULT NULL COMMENT '活动类型(coupon/full_reduction/flash_sale/bundle)',
    discount_value  DECIMAL(10,2) DEFAULT NULL COMMENT '优惠力度(金额或折扣率)',
    start_date      VARCHAR(20)   DEFAULT NULL COMMENT '开始日期',
    end_date        VARCHAR(20)   DEFAULT NULL COMMENT '结束日期',
    etl_time        DATETIME      DEFAULT CURRENT_TIMESTAMP COMMENT 'ETL加载时间',
    PRIMARY KEY (promotion_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='ODS-促销活动原始表';
