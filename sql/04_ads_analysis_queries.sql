-- ============================================================
-- 电商销售数据分析 — ADS 层：业务分析查询
-- 包含: Pareto 分析 / AARRR 漏斗 / Cohort 同期群 / RFM 分群
-- 共 10+ 条复杂 SQL，覆盖 CTE / 窗口函数 / 子查询 / 多表 JOIN
-- ============================================================
USE ecommerce_sales;

-- ============================================================
-- 【查询1】月度 GMV 趋势与环比增长率
-- 技术点: 窗口函数 LAG()
-- ============================================================
SELECT
    year_month,
    order_cnt,
    customer_cnt,
    gross_revenue,
    net_revenue,
    avg_order_value,
    CONCAT(ROUND(
        (gross_revenue - LAG(gross_revenue) OVER (ORDER BY year_month))
        / LAG(gross_revenue) OVER (ORDER BY year_month) * 100, 1
    ), '%') AS mom_growth_pct   -- 环比增长率
FROM (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m')               AS year_month,
        COUNT(DISTINCT order_id)                        AS order_cnt,
        COUNT(DISTINCT customer_id)                     AS customer_cnt,
        ROUND(SUM(total_amount), 2)                     AS gross_revenue,
        ROUND(SUM(actual_amount), 2)                    AS net_revenue,
        ROUND(AVG(total_amount), 2)                     AS avg_order_value
    FROM dwd_order_fact
    WHERE order_status != 'cancelled'
    GROUP BY DATE_FORMAT(order_date, '%Y-%m')
) t
ORDER BY year_month;


-- ============================================================
-- 【查询2】Pareto 分析：Top N 品类贡献度（累计收入占比）
-- 技术点: SUM() OVER() 窗口函数 + CASE 分级
-- ============================================================
WITH category_revenue AS (
    SELECT
        category,
        SUM(total_amount) AS category_revenue,
        ROUND(SUM(total_amount) / SUM(SUM(total_amount)) OVER(), 4) AS revenue_share_pct
    FROM dwd_order_fact
    WHERE order_status != 'cancelled'
    GROUP BY category
),
cumulative AS (
    SELECT
        category,
        category_revenue,
        revenue_share_pct,
        SUM(revenue_share_pct) OVER (ORDER BY category_revenue DESC) AS cum_share,
        ROW_NUMBER() OVER (ORDER BY category_revenue DESC) AS revenue_rank
    FROM category_revenue
)
SELECT
    revenue_rank,
    category,
    ROUND(category_revenue, 2)   AS revenue,
    CONCAT(ROUND(revenue_share_pct * 100, 1), '%')  AS share_pct,
    CONCAT(ROUND(cum_share * 100, 1), '%')          AS cum_share_pct,
    CASE WHEN cum_share <= 0.80 THEN 'A类-核心品类'
         WHEN cum_share <= 0.95 THEN 'B类-成长品类'
         ELSE 'C类-长尾品类'
    END AS abc_level
FROM cumulative
ORDER BY revenue_rank;


-- ============================================================
-- 【查询3】AARRR 用户生命周期漏斗分析
-- 技术点: 多步 CTE 链式处理 + LEFT JOIN 保留层级
-- ============================================================
WITH total_users AS (
    SELECT COUNT(DISTINCT customer_id) AS cnt FROM dim_customer
),
pv_users AS (
    SELECT COUNT(DISTINCT customer_id) AS cnt FROM dwd_order_fact
),
cart_users AS (
    SELECT COUNT(DISTINCT customer_id) AS cnt
    FROM dwd_order_fact WHERE order_status IN ('pending', 'paid', 'shipped', 'cancelled', 'returned')
),
pay_users AS (
    SELECT COUNT(DISTINCT customer_id) AS cnt
    FROM dwd_order_fact WHERE order_status IN ('paid', 'shipped', 'returned')
),
repay_users AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS orders
    FROM dwd_order_fact WHERE order_status IN ('paid', 'shipped', 'returned')
    GROUP BY customer_id
    HAVING orders >= 2
)
SELECT
    '1-注册用户'          AS funnel_stage,
    (SELECT cnt FROM total_users) AS user_cnt,
    100.0 AS overall_rate
UNION ALL
SELECT
    '2-有购买行为',
    (SELECT cnt FROM pv_users),
    ROUND((SELECT cnt FROM pv_users) / (SELECT cnt FROM total_users) * 100, 1)
UNION ALL
SELECT
    '3-产生订单',
    (SELECT cnt FROM cart_users),
    ROUND((SELECT cnt FROM cart_users) / (SELECT cnt FROM total_users) * 100, 1)
UNION ALL
SELECT
    '4-完成支付',
    (SELECT cnt FROM pay_users),
    ROUND((SELECT cnt FROM pay_users) / (SELECT cnt FROM total_users) * 100, 1)
UNION ALL
SELECT
    '5-复购用户',
    (SELECT COUNT(*) FROM repay_users),
    ROUND((SELECT COUNT(*) FROM repay_users) / (SELECT cnt FROM total_users) * 100, 1);


-- ============================================================
-- 【查询4】同期群留存分析（Cohort Retention Matrix）
-- 技术点: 自连接 + 条件聚合 + GROUP BY 多维分组
-- ============================================================
WITH cohort_base AS (
    SELECT
        customer_id,
        DATE_FORMAT(MIN(order_date), '%Y-%m') AS cohort_month,
        MAX(order_date) AS last_active_date,
        DATEDIFF(MAX(order_date), MIN(order_date)) AS lifecycle_days
    FROM dwd_order_fact
    WHERE order_status != 'cancelled'
    GROUP BY customer_id
),
cohort_monthly AS (
    SELECT
        b.cohort_month,
        DATE_FORMAT(o.order_date, '%Y-%m') AS activity_month,
        COUNT(DISTINCT o.customer_id) AS active_users
    FROM cohort_base b
    JOIN dwd_order_fact o ON b.customer_id = o.customer_id
    WHERE o.order_status != 'cancelled'
    GROUP BY b.cohort_month, DATE_FORMAT(o.order_date, '%Y-%m')
),
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_id) AS initial_users
    FROM cohort_base
    GROUP BY cohort_month
)
SELECT
    s.cohort_month,
    s.initial_users,
    m.activity_month,
    m.active_users,
    -- 计算每个同期群的时期序号 (period_index)
    ROUND((TIMESTAMPDIFF(MONTH,
        STR_TO_DATE(CONCAT(s.cohort_month, '-01'), '%Y-%m-%d'),
        STR_TO_DATE(CONCAT(m.activity_month, '-01'), '%Y-%m-%d'))
    ), 0) AS period_index,
    -- 留存率 = 当期活跃 / 同期群初始人数
    ROUND(m.active_users / s.initial_users * 100, 2) AS retention_pct
FROM cohort_size s
JOIN cohort_monthly m ON s.cohort_month = m.cohort_month
WHERE m.activity_month >= s.cohort_month
ORDER BY s.cohort_month, period_index;


-- ============================================================
-- 【查询5】RFM 客户价值分群（百分位打分法）
-- 技术点: NTILE() 窗口函数 + CASE 多条件分群
-- ============================================================
WITH rfm_scored AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        monetary,
        -- R: 最近一次越近得分越高（反转）
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        -- F: 频次越高得分越高
        NTILE(5) OVER (ORDER BY frequency ASC)      AS f_score,
        -- M: 金额越高得分越高
        NTILE(5) OVER (ORDER BY monetary ASC)       AS m_score
    FROM dws_customer_behavior
)
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    r_score, f_score, m_score,
    CONCAT(r_score, f_score, m_score)         AS rfm_cell,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '高价值用户'
        WHEN r_score >= 4 AND f_score <= 2 AND m_score >= 3 THEN '重点挽回用户'
        WHEN r_score >= 4 AND f_score >= 4 AND m_score <= 2 THEN '潜力用户'
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN '核心用户'
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN '流失预警用户'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score >= 3 THEN '一次性高消费用户'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN '流失用户'
        ELSE '普通用户'
    END                                         AS rfm_segment
FROM rfm_scored
ORDER BY rfm_segment, monetary DESC;


-- ============================================================
-- 【查询6】品类交叉购买分析（购物篮关联）
-- 技术点: 自连接 + HAVING + 组合计数
-- ============================================================
WITH order_categories AS (
    SELECT DISTINCT
        customer_id,
        order_id,
        category
    FROM dwd_order_fact
    WHERE order_status != 'cancelled'
)
SELECT
    a.category    AS category_a,
    b.category    AS category_b,
    COUNT(DISTINCT a.order_id) AS co_occurrence_cnt,
    ROUND(COUNT(DISTINCT a.order_id) /
        (SELECT COUNT(DISTINCT order_id) FROM dwd_order_fact WHERE order_status != 'cancelled') * 100, 2
    ) AS co_occurrence_pct
FROM order_categories a
JOIN order_categories b
    ON a.order_id = b.order_id
    AND a.category < b.category   -- 避免自反和重复组合
GROUP BY a.category, b.category
HAVING co_occurrence_cnt >= 10
ORDER BY co_occurrence_cnt DESC
LIMIT 20;


-- ============================================================
-- 【查询7】促销活动 ROI 排名
-- 技术点: 多表 JOIN + 标量子查询 + 排序
-- ============================================================
SELECT
    p.promotion_name,
    p.promotion_type,
    p.discount_value,
    e.promo_order_cnt,
    e.promo_customer_cnt,
    e.gross_revenue,
    e.discount_total,
    -- ROI = 活动收入 / 让利成本
    ROUND(e.gross_revenue / NULLIF(e.discount_total, 0), 2)   AS promotion_roi,
    e.avg_promo_order_val,
    -- 整体平均客单价（用于对比）
    ROUND((SELECT AVG(total_amount) FROM dwd_order_fact WHERE order_status != 'cancelled'), 2) AS overall_avg_order_val,
    -- 活动客单价是否高于整体
    CASE WHEN e.avg_promo_order_val > (SELECT AVG(total_amount) FROM dwd_order_fact WHERE order_status != 'cancelled')
         THEN '高于整体' ELSE '低于整体' END                    AS avg_val_vs_overall
FROM dws_promotion_effect e
JOIN dim_promotion p ON e.promotion_id = p.promotion_id
ORDER BY promotion_roi DESC;


-- ============================================================
-- 【查询8】区域销售分析（含分布集中度）
-- 技术点: ROW_NUMBER() + 子查询透视
-- ============================================================
WITH regional_sales AS (
    SELECT
        c.region,
        COUNT(DISTINCT f.order_id)                                    AS order_cnt,
        COUNT(DISTINCT f.customer_id)                                 AS customer_cnt,
        ROUND(SUM(f.total_amount), 2)                                 AS total_revenue,
        ROUND(SUM(f.total_amount) / SUM(SUM(f.total_amount)) OVER(), 4) AS revenue_share,
        ROUND(AVG(f.total_amount), 2)                                 AS avg_order_val,
        ROUND(AVG(f.discount_rate), 3)                                AS avg_discount_rate,
        ROUND(AVG(f.ship_interval), 1)                                AS avg_ship_days
    FROM dwd_order_fact f
    JOIN dim_customer c ON f.customer_id = c.customer_id
    WHERE f.order_status != 'cancelled'
    GROUP BY c.region
)
SELECT
    region,
    order_cnt,
    customer_cnt,
    total_revenue,
    CONCAT(ROUND(revenue_share * 100, 1), '%')  AS revenue_share_pct,
    avg_order_val,
    avg_discount_rate,
    avg_ship_days,
    RANK() OVER (ORDER BY total_revenue DESC)    AS revenue_rank,
    -- 集中度标记
    SUM(revenue_share) OVER (ORDER BY total_revenue DESC) AS cum_share
FROM regional_sales
ORDER BY total_revenue DESC;


-- ============================================================
-- 【查询9】客户生命周期价值（LTV）估算
-- 技术点: CTE 多层嵌套 + 窗口函数
-- ============================================================
WITH customer_ltv AS (
    -- 计算每个客户每月的消费
    SELECT
        customer_id,
        DATE_FORMAT(order_date, '%Y-%m') AS order_month,
        COUNT(DISTINCT order_id)         AS monthly_orders,
        ROUND(SUM(total_amount), 2)      AS monthly_revenue
    FROM dwd_order_fact
    WHERE order_status != 'cancelled'
    GROUP BY customer_id, DATE_FORMAT(order_date, '%Y-%m')
),
customer_monthly_avg AS (
    -- 计算客户月均消费
    SELECT
        customer_id,
        COUNT(DISTINCT order_month)      AS active_months,
        ROUND(AVG(monthly_revenue), 2)   AS avg_monthly_revenue,
        -- 估算 LTV = 月均消费 × 12 个月（假设年均预测）
        ROUND(AVG(monthly_revenue) * 12, 2) AS estimated_ltv
    FROM customer_ltv
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    cb.total_gross,
    cma.avg_monthly_revenue,
    cma.estimated_ltv,
    cb.top_category,
    CASE
        WHEN cma.estimated_ltv >= 5000 THEN '高 LTV'
        WHEN cma.estimated_ltv >= 2000 THEN '中 LTV'
        ELSE '低 LTV'
    END AS ltv_tier
FROM customer_monthly_avg cma
JOIN dws_customer_behavior cb ON cma.customer_id = cb.customer_id
ORDER BY cma.estimated_ltv DESC
LIMIT 100;


-- ============================================================
-- 【查询10】周度销售热力图数据（时段分析）
-- 技术点: PIVOT 风格的条件聚合 + WEEKDAY 分级
-- ============================================================
SELECT
    order_year,
    order_month,
    SUM(CASE WHEN order_weekday = 0 THEN 1 ELSE 0 END) AS mon_orders,
    SUM(CASE WHEN order_weekday = 1 THEN 1 ELSE 0 END) AS tue_orders,
    SUM(CASE WHEN order_weekday = 2 THEN 1 ELSE 0 END) AS wed_orders,
    SUM(CASE WHEN order_weekday = 3 THEN 1 ELSE 0 END) AS thu_orders,
    SUM(CASE WHEN order_weekday = 4 THEN 1 ELSE 0 END) AS fri_orders,
    SUM(CASE WHEN order_weekday = 5 THEN 1 ELSE 0 END) AS sat_orders,
    SUM(CASE WHEN order_weekday = 6 THEN 1 ELSE 0 END) AS sun_orders,
    COUNT(*) AS total_orders,
    -- 周末占比
    ROUND(SUM(CASE WHEN is_weekend = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS weekend_pct
FROM dwd_order_fact
WHERE order_status != 'cancelled'
GROUP BY order_year, order_month
ORDER BY order_year, order_month;
