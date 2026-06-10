-- ============================================================
-- 电商销售数据分析 — DWS 层：汇总聚合
-- 功能: 构建分析级中间表，支撑上层业务查询
-- ============================================================
USE ecommerce_sales;

-- ============================================================
-- DWS-1: 日度销售汇总表
-- ============================================================
DROP TABLE IF EXISTS dws_daily_sales;
CREATE TABLE dws_daily_sales AS
SELECT
    order_date,
    order_year,
    order_month,
    order_weekday,
    is_weekend,
    -- 订单维度
    COUNT(DISTINCT order_id)                                         AS order_cnt,
    COUNT(DISTINCT customer_id)                                      AS customer_cnt,
    -- 金额维度
    ROUND(SUM(total_amount), 2)                                      AS gross_revenue,      -- 毛收入
    ROUND(SUM(actual_amount), 2)                                     AS net_revenue,        -- 实收
    ROUND(SUM(total_amount) - SUM(actual_amount), 2)                 AS discount_loss,      -- 优惠让利
    ROUND(AVG(total_amount), 2)                                      AS avg_order_value,    -- 客单价
    -- 销售维度
    SUM(quantity)                                                    AS total_qty_sold,
    ROUND(AVG(quantity), 1)                                          AS avg_qty_per_order,
    -- 促销维度
    SUM(is_promotion)                                                AS promo_order_cnt,
    ROUND(SUM(is_promotion) / COUNT(*), 4)                           AS promo_order_rate,
    -- 退货维度
    SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END)       AS return_order_cnt,
    ROUND(SUM(CASE WHEN order_status = 'returned' THEN 1 ELSE 0 END) / COUNT(*), 4) AS return_rate
FROM dwd_order_fact
GROUP BY order_date, order_year, order_month, order_weekday, is_weekend;

ALTER TABLE dws_daily_sales ADD PRIMARY KEY (order_date);
ALTER TABLE dws_daily_sales ADD INDEX idx_month (order_year, order_month);


-- ============================================================
-- DWS-2: 类目月度销售汇总表
-- ============================================================
DROP TABLE IF EXISTS dws_category_monthly;
CREATE TABLE dws_category_monthly AS
SELECT
    category,
    sub_category,
    order_year,
    order_month,
    DATE(CONCAT(order_year, '-', LPAD(order_month, 2, '0'), '-01')) AS month_start,
    COUNT(DISTINCT order_id)                                         AS order_cnt,
    SUM(quantity)                                                    AS total_qty,
    ROUND(SUM(total_amount), 2)                                      AS gross_revenue,
    ROUND(SUM(actual_amount), 2)                                     AS net_revenue,
    ROUND(SUM(total_amount) / SUM(SUM(total_amount)) OVER (PARTITION BY order_year, order_month), 4) AS revenue_share_pct,
    ROUND(AVG(unit_price), 2)                                        AS avg_unit_price,
    ROUND(AVG(discount_rate), 2)                                     AS avg_discount_rate
FROM dwd_order_fact
WHERE order_status != 'cancelled'
GROUP BY category, sub_category, order_year, order_month;

ALTER TABLE dws_category_monthly ADD INDEX idx_cat_month (category, order_year, order_month);


-- ============================================================
-- DWS-3: 客户消费行为汇总表（RFM 基础数据源）
-- ============================================================
DROP TABLE IF EXISTS dws_customer_behavior;
CREATE TABLE dws_customer_behavior (
    customer_id         VARCHAR(32)  NOT NULL,
    -- 消费概况
    first_order_date    DATE         DEFAULT NULL,
    last_order_date     DATE         DEFAULT NULL,
    total_orders        INT          DEFAULT 0,
    total_qty           INT          DEFAULT 0,
    total_gross         DECIMAL(14,2) DEFAULT 0,
    total_net           DECIMAL(14,2) DEFAULT 0,
    avg_order_value     DECIMAL(10,2) DEFAULT 0,
    -- 品类偏好
    top_category        VARCHAR(100) DEFAULT NULL,
    category_cnt        INT          DEFAULT 0 COMMENT '购买过的类目数',
    -- 促销依赖度
    promo_order_rate    DECIMAL(4,2)  DEFAULT 0 COMMENT '参与促销的订单占比',
    -- 退货倾向
    return_order_cnt    INT          DEFAULT 0,
    return_rate         DECIMAL(4,3)  DEFAULT 0,
    -- RFM 指标
    recency_days        INT          DEFAULT NULL COMMENT '距今天数',
    frequency           INT          DEFAULT 0 COMMENT '购买次数',
    monetary            DECIMAL(14,2) DEFAULT 0 COMMENT '累计消费金额',
    -- 同期群
    cohort_month        VARCHAR(7)   DEFAULT NULL,
    PRIMARY KEY (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='DWS-客户消费行为汇总';

INSERT INTO dws_customer_behavior
SELECT
    f.customer_id,
    MIN(f.order_date)                                                      AS first_order_date,
    MAX(f.order_date)                                                      AS last_order_date,
    COUNT(DISTINCT f.order_id)                                             AS total_orders,
    SUM(f.quantity)                                                        AS total_qty,
    ROUND(SUM(f.total_amount), 2)                                          AS total_gross,
    ROUND(SUM(f.actual_amount), 2)                                         AS total_net,
    ROUND(SUM(f.total_amount) / COUNT(DISTINCT f.order_id), 2)             AS avg_order_value,
    -- 使用窗口函数找 top1 品类
    (SELECT t.category
     FROM (SELECT category, SUM(total_amount) AS rev
           FROM dwd_order_fact WHERE customer_id = f.customer_id AND order_status != 'cancelled'
           GROUP BY category ORDER BY rev DESC LIMIT 1) t
    )                                                                      AS top_category,
    COUNT(DISTINCT f.category)                                             AS category_cnt,
    ROUND(SUM(f.is_promotion) / COUNT(DISTINCT f.order_id), 2)             AS promo_order_rate,
    SUM(CASE WHEN f.order_status = 'returned' THEN 1 ELSE 0 END)           AS return_order_cnt,
    ROUND(SUM(CASE WHEN f.order_status = 'returned' THEN 1 ELSE 0 END) / COUNT(DISTINCT f.order_id), 3) AS return_rate,
    -- 计算 RFM
    DATEDIFF((SELECT MAX(order_date) FROM dwd_order_fact), MAX(f.order_date)) AS recency_days,
    COUNT(DISTINCT f.order_id)                                             AS frequency,
    ROUND(SUM(f.total_amount), 2)                                          AS monetary,
    c.cohort_month
FROM dwd_order_fact f
LEFT JOIN dim_customer c ON f.customer_id = c.customer_id
WHERE f.order_status != 'cancelled'
GROUP BY f.customer_id, c.cohort_month;


-- ============================================================
-- DWS-4: 促销活动效果汇总表
-- ============================================================
DROP TABLE IF EXISTS dws_promotion_effect;
CREATE TABLE dws_promotion_effect AS
SELECT
    f.promotion_id,
    p.promotion_name,
    p.promotion_type,
    p.discount_value,
    -- 参与情况
    COUNT(DISTINCT f.order_id)                                      AS promo_order_cnt,
    COUNT(DISTINCT f.customer_id)                                   AS promo_customer_cnt,
    -- 金额
    ROUND(SUM(f.total_amount), 2)                                   AS gross_revenue,
    ROUND(SUM(f.actual_amount), 2)                                  AS net_revenue,
    ROUND(SUM(f.total_amount) - SUM(f.actual_amount), 2)            AS discount_total,
    -- 客单价对比（促销 vs 非促销）
    ROUND(AVG(f.total_amount), 2)                                   AS avg_promo_order_val,
    ROUND(AVG(f.discount_rate), 3)                                  AS avg_discount_rate,
    -- 退货率
    ROUND(SUM(CASE WHEN f.order_status = 'returned' THEN 1 ELSE 0 END) / COUNT(*), 4) AS promo_return_rate
FROM dwd_order_fact f
LEFT JOIN dim_promotion p ON f.promotion_id = p.promotion_id
WHERE f.promotion_id IS NOT NULL
GROUP BY f.promotion_id, p.promotion_name, p.promotion_type, p.discount_value;

ALTER TABLE dws_promotion_effect ADD PRIMARY KEY (promotion_id);
