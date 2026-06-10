# 电商平台销售数据分析与经营洞察

> 端到端 SQL 数据分析项目 — 从数据仓库分层到业务洞察的全链路实践

## 项目概述

基于某电商平台 2 年、12 万条订单数据，使用 SQL 数据仓库分层架构（ODS → DWD → DWS → ADS），完成从数据清洗、多层次聚合到 10+ 条业务分析查询的完整链路。结合 Python 可视化输出经营洞察报告，Power BI DAX 度量值支持动态仪表板。

## 技术栈

- **SQL (MySQL)**: 数据仓库分层设计(ODS/DWD/DWS/ADS)、CTE、窗口函数、子查询、多表 JOIN
- **Python**: Pandas 数据清洗、Matplotlib/Seaborn 可视化、EDA 分析
- **Power BI**: DAX 度量值、动态切片、KPI 看板
- **分析方法**: AARRR 漏斗、Pareto 20/80、RFM 客户分群、Cohort 同期群留存、LTV 估算

## 项目结构

```
ecommerce-sales-analysis/
├── README.md
├── sql/
│   ├── 01_ods_raw_tables.sql         # ODS 层: 3 张原始表 DDL
│   ├── 02_dwd_dim_fact.sql           # DWD 层: 维度表 + 事实宽表 + ETL
│   ├── 03_dws_agg_metrics.sql        # DWS 层: 4 张汇总聚合表
│   └── 04_ads_analysis_queries.sql   # ADS 层: 10 条业务分析 SQL
├── python/
│   ├── config.py                     # 全局配置
│   ├── data_cleaning.py              # 数据清洗脚本
│   ├── eda_analysis.py               # 探索性数据分析
│   ├── aarrr_funnel.py               # AARRR 漏斗 + Pareto 分析
│   └── visualization.py              # 可视化图表生成(5张)
├── data/
│   └── schema_overview.md            # 数据模型设计文档
└── powerbi/
    └── measures_dax.txt              # Power BI DAX 度量值(15条)
```

## 数据分层架构

| 层级 | 说明 | 输出 |
|------|------|------|
| **ODS** | 原始数据层 | 3 张原始表 |
| **DWD** | 明细数据层 | 1 张订单事实宽表 + 4 张维度表(日期/客户/商品/促销) |
| **DWS** | 汇总聚合层 | 日度销售汇总 / 品类月度 / 客户行为(RFM源) / 促销效果 |
| **ADS** | 应用分析层 | 10 条业务 SQL: Pareto / Cohort / RFM / LTV / 区域 / 时序 |

## 核心分析指标

- **GMV & 增长**: 月环比增长率、客单价趋势、折扣对收入的影响
- **用户漏斗**: 注册→购买→支付→复购 各层转化率与流失诊断
- **品类 ABC**: Top 20% 品类贡献 80% GMV 的 Pareto 验证
- **RFM 分群**: 7 类客户群体(高价值/核心/流失预警/重点挽回等)
- **同期群留存**: 每月获取的客户在各月留存率矩阵
- **促销 ROI**: 各活动投入产出比排名
- **LTV 预估**: 客户生命周期价值分层

## 运行说明

```bash
# 1. SQL 执行顺序
mysql -u root -p < sql/01_ods_raw_tables.sql
mysql -u root -p < sql/02_dwd_dim_fact.sql
mysql -u root -p < sql/03_dws_agg_metrics.sql
mysql -u root -p < sql/04_ads_analysis_queries.sql

# 2. Python 分析
pip install pandas numpy matplotlib seaborn
python python/eda_analysis.py
python python/aarrr_funnel.py
python python/visualization.py
```
