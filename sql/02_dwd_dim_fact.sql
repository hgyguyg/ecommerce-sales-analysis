-- ============================================================
-- 电商销售数据分析 — DWD 层：维度表 & 事实表
-- 功能: 数据清洗、类型转换、日期标准化、衍生字段
-- ============================================================
USE ecommerce_sales;

-- ============================================================
-- DWD: 日期维度表
-- ============================================================
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date AS
SELECT DISTINCT
    DATE(order_date)                 AS date_id,
    YEAR(order_date)                 AS year,
    QUARTER(order_date)              AS quarter,
    MONTH(order_date)                AS month,
    DAY(order_date)                  AS day,
    WEEKDAY(order_date)              AS weekday,        -- 0=Monday
    CASE WEEKDAY(order_date)
        WHEN 5 THEN '周六'
        WHEN 6 THEN '周日'
        ELSE '工作日'
    END                              AS day_type,
    DATE_FORMAT(order_date, '%Y-%m') AS year_month,
    DATE_FORMAT(order_date, '%Y-W%u') AS year_week
FROM ods_orders_raw
WHERE order_date IS NOT NULL
  AND STR_TO_DATE(order_date, '%Y-%m-%d') IS NOT NULL;

ALTER TABLE dim_date ADD PRIMARY KEY (date_id);


-- ============================================================
-- DWD: 客户维度表（含地域信息展开）
-- ============================================================
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (
    customer_id    VARCHAR(32)  NOT NULL,
    segment        VARCHAR(20)  DEFAULT NULL COMMENT '客户分层',
    city           VARCHAR(50)  DEFAULT NULL,
    region         VARCHAR(20)  DEFAULT NULL COMMENT '大区',
    province       VARCHAR(30)  DEFAULT NULL COMMENT '省份(从城市推导)',
    register_date  DATE         DEFAULT NULL,
    cohort_month   VARCHAR(7)   DEFAULT NULL COMMENT '同期群月份 YYYY-MM',
    PRIMARY KEY (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_customer (customer_id, segment, city, region, register_date, cohort_month)
SELECT
    customer_id,
    segment,
    city,
    region,
    STR_TO_DATE(register_date, '%Y-%m-%d'),
    DATE_FORMAT(STR_TO_DATE(register_date, '%Y-%m-%d'), '%Y-%m')
FROM ods_customers_raw
WHERE STR_TO_DATE(register_date, '%Y-%m-%d') IS NOT NULL;


-- ============================================================
-- DWD: 商品维度表
-- ============================================================
DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product AS
SELECT
    product_name,
    category,
    sub_category,
    MIN(unit_price)                                                 AS min_unit_price,
    MAX(unit_price)                                                 AS max_unit_price,
    ROUND(AVG(unit_price), 2)                                       AS avg_unit_price,
    ROUND(STDDEV(unit_price), 2)                                    AS price_volatility,
    COUNT(DISTINCT order_id)                                        AS total_orders,
    SUM(quantity)                                                   AS total_sold_qty,
    ROUND(SUM(total_amount), 2)                                     AS total_revenue,
    -- 商品价格带分类
    CASE WHEN AVG(unit_price) < 50  THEN '低单价(<50)'
         WHEN AVG(unit_price) < 200 THEN '中单价(50-200)'
         ELSE '高单价(>=200)'
    END                                                             AS price_tier,
    RANK() OVER (PARTITION BY category ORDER BY SUM(total_amount) DESC) AS category_rank
FROM ods_orders_raw
WHERE total_amount IS NOT NULL
  AND quantity > 0
GROUP BY product_name, category, sub_category;

ALTER TABLE dim_product ADD PRIMARY KEY (product_name);


-- ============================================================
-- DWD: 促销活动维度表
-- ============================================================
DROP TABLE IF EXISTS dim_promotion;
CREATE TABLE dim_promotion (
    promotion_id    VARCHAR(32)  NOT NULL,
    promotion_name  VARCHAR(200) DEFAULT NULL,
    promotion_type  VARCHAR(30)  DEFAULT NULL,
    discount_value  DECIMAL(10,2) DEFAULT NULL,
    start_date      DATE         DEFAULT NULL,
    end_date        DATE         DEFAULT NULL,
    duration_days   INT          DEFAULT NULL,
    PRIMARY KEY (promotion_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dim_promotion
SELECT
    promotion_id,
    promotion_name,
    promotion_type,
    discount_value,
    STR_TO_DATE(start_date, '%Y-%m-%d'),
    STR_TO_DATE(end_date, '%Y-%m-%d'),
    DATEDIFF(STR_TO_DATE(end_date, '%Y-%m-%d'), STR_TO_DATE(start_date, '%Y-%m-%d'))
FROM ods_promotions_raw
WHERE STR_TO_DATE(start_date, '%Y-%m-%d') IS NOT NULL;


-- ============================================================
-- DWD: 订单事实表（清洗后的宽表）
-- ============================================================
DROP TABLE IF EXISTS dwd_order_fact;
CREATE TABLE dwd_order_fact (
    order_id        VARCHAR(32)   NOT NULL,
    customer_id     VARCHAR(32)   NOT NULL,
    product_name    VARCHAR(200)  DEFAULT NULL,
    category        VARCHAR(100)  DEFAULT NULL,
    sub_category    VARCHAR(100)  DEFAULT NULL,
    unit_price      DECIMAL(10,2) DEFAULT NULL,
    quantity        INT           DEFAULT NULL,
    total_amount    DECIMAL(12,2) DEFAULT NULL,
    -- 衍生字段: 实际支付金额 = 总金额 × (1 - 折扣率)
    actual_amount   DECIMAL(12,2) DEFAULT NULL,
    discount_rate   DECIMAL(4,2)  DEFAULT 0,
    payment_method  VARCHAR(20)   DEFAULT NULL,
    order_status    VARCHAR(20)   DEFAULT NULL,
    promotion_id    VARCHAR(32)   DEFAULT NULL,
    order_date      DATE          NOT NULL,
    ship_date       DATE          DEFAULT NULL,
    -- 衍生字段: 发货间隔(天)
    ship_interval   INT           DEFAULT NULL,
    -- 时间维度派生
    order_year      SMALLINT      DEFAULT NULL,
    order_month     TINYINT       DEFAULT NULL,
    order_weekday   TINYINT       DEFAULT NULL,
    order_hour      TINYINT       DEFAULT NULL COMMENT '下单时段(预留)',
    -- 标记字段
    is_weekend      TINYINT(1)    DEFAULT 0 COMMENT '是否周末',
    is_promotion    TINYINT(1)    DEFAULT 0 COMMENT '是否促销订单',
    PRIMARY KEY (order_id),
    INDEX idx_customer   (customer_id),
    INDEX idx_order_date (order_date),
    INDEX idx_category   (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='DWD-订单事实表';

-- ETL: 清洗+转换
INSERT INTO dwd_order_fact
SELECT
    o.order_id,
    o.customer_id,
    o.product_name,
    o.category,
    o.sub_category,
    o.unit_price,
    o.quantity,
    o.total_amount,
    CASE WHEN o.discount_rate IS NOT NULL AND o.total_amount IS NOT NULL
         THEN ROUND(o.total_amount * (1 - o.discount_rate), 2)
         ELSE o.total_amount
    END                                                       AS actual_amount,
    COALESCE(o.discount_rate, 0)                              AS discount_rate,
    o.payment_method,
    o.order_status,
    o.promotion_id,
    DATE(STR_TO_DATE(o.order_date, '%Y-%m-%d'))               AS order_date,
    IFNULL(DATE(STR_TO_DATE(o.ship_date, '%Y-%m-%d')), NULL)  AS ship_date,
    CASE WHEN o.ship_date IS NOT NULL
         THEN DATEDIFF(DATE(STR_TO_DATE(o.ship_date, '%Y-%m-%d')),
                       DATE(STR_TO_DATE(o.order_date, '%Y-%m-%d')))
         ELSE NULL END                                        AS ship_interval,
    YEAR(STR_TO_DATE(o.order_date, '%Y-%m-%d'))               AS order_year,
    MONTH(STR_TO_DATE(o.order_date, '%Y-%m-%d'))              AS order_month,
    WEEKDAY(STR_TO_DATE(o.order_date, '%Y-%m-%d'))            AS order_weekday,
    NULL                                                      AS order_hour,
    CASE WHEN WEEKDAY(STR_TO_DATE(o.order_date, '%Y-%m-%d')) IN (5,6) THEN 1 ELSE 0 END AS is_weekend,
    CASE WHEN o.promotion_id IS NOT NULL THEN 1 ELSE 0 END    AS is_promotion
FROM ods_orders_raw o
WHERE STR_TO_DATE(o.order_date, '%Y-%m-%d') IS NOT NULL
  AND o.quantity > 0
  AND o.total_amount > 0;
