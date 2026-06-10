# ============================================================
# 电商销售数据分析 — EDA 探索性分析
# 功能: 数据概况 / 分布检查 / 相关性 / 缺失值统计
# ============================================================
import pandas as pd
import numpy as np
from pathlib import Path

INPUT_DIR = Path("data/processed")

orders = pd.read_csv(INPUT_DIR / "orders_cleaned.csv", parse_dates=["order_date", "ship_date"])
customers = pd.read_csv(INPUT_DIR / "customers_cleaned.csv", parse_dates=["register_date"])

# === 1. 数据概况 ===
print("=" * 50)
print("【数据概况】")
print(f"订单记录: {len(orders):,}")
print(f"客户数量: {orders['customer_id'].nunique():,}")
print(f"商品种类: {orders['product_name'].nunique():,}")
print(f"时间跨度: {orders['order_date'].min().date()} ~ {orders['order_date'].max().date()}")
print(f"总 GMV: ¥{orders['total_amount'].sum():,.2f}")

# === 2. 订单状态分布 ===
print("\n【订单状态分布】")
status_dist = orders["order_status"].value_counts()
for status, cnt in status_dist.items():
    print(f"  {status}: {cnt:,} ({cnt/len(orders)*100:.1f}%)")

# === 3. 类目维度 ===
print("\n【类目 Top 5 by GMV】")
cat_gmv = orders.groupby("category")["total_amount"].sum().sort_values(ascending=False)
for i, (cat, gmv) in enumerate(cat_gmv.head(5).items(), 1):
    share = gmv / cat_gmv.sum() * 100
    print(f"  {i}. {cat}: ¥{gmv:,.0f} ({share:.1f}%)")

# === 4. 客单价分布 ===
print("\n【客单价统计】")
print(f"  均值: ¥{orders['total_amount'].mean():.2f}")
print(f"  中位数: ¥{orders['total_amount'].median():.2f}")
print(f"  P25: ¥{orders['total_amount'].quantile(0.25):.2f}")
print(f"  P75: ¥{orders['total_amount'].quantile(0.75):.2f}")
print(f"  P95: ¥{orders['total_amount'].quantile(0.95):.2f}")

# === 5. 月趋势 ===
orders["year_month"] = orders["order_date"].dt.to_period("M")
monthly = orders.groupby("year_month").agg(
    orders=("order_id", "nunique"),
    customers=("customer_id", "nunique"),
    gmv=("total_amount", "sum"),
    avg_order=("total_amount", "mean")
)
print(f"\n【月度趋势】(共 {len(monthly)} 个月)")
print(monthly.tail(6).round(1).to_string())

# === 6. 客户分层 ===
customer_orders = orders.groupby("customer_id").agg(
    total_orders=("order_id", "nunique"),
    total_spend=("total_amount", "sum"),
    first_order=("order_date", "min"),
    last_order=("order_date", "max")
)
print(f"\n【客户分层】")
print(f"  单次购买: {(customer_orders['total_orders'] == 1).sum()} ({(customer_orders['total_orders']==1).mean()*100:.1f}%)")
print(f"  复购(2-5次): {((customer_orders['total_orders'] >= 2) & (customer_orders['total_orders'] <= 5)).sum()}")
print(f"  重度(>5次): {(customer_orders['total_orders'] > 5).sum()}")

# === 7. 区域分布 ===
region = orders.merge(customers[["customer_id", "region"]], on="customer_id", how="left")
print(f"\n【区域 GMV 分布 Top 5】")
for reg, gmv in region.groupby("region")["total_amount"].sum().sort_values(ascending=False).head(5).items():
    share = gmv / region["total_amount"].sum() * 100
    print(f"  {reg}: ¥{gmv:,.0f} ({share:.1f}%)")

print("\n✅ EDA 分析完成")
