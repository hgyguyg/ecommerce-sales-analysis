# ============================================================
# 电商销售数据分析 — AARRR 漏斗 & Pareto 分析
# 功能: 用户生命周期漏斗 / Pareto 20/80 分析 / 流失诊断
# ============================================================
import pandas as pd
import numpy as np
from pathlib import Path

INPUT_DIR = Path("data/processed")

orders = pd.read_csv(INPUT_DIR / "orders_cleaned.csv", parse_dates=["order_date", "ship_date"])
customers = pd.read_csv(INPUT_DIR / "customers_cleaned.csv", parse_dates=["register_date"])

# === 1. AARRR 漏斗 ===
print("=" * 50)
print("【AARRR 用户生命周期漏斗】")

total_users = len(customers)
pv_users = orders["customer_id"].nunique()
pay_users = orders[orders["order_status"].isin(["paid", "shipped", "returned"])]["customer_id"].nunique()
repurchase_users = orders[orders["order_status"].isin(["paid", "shipped", "returned"])]\
    .groupby("customer_id")["order_id"].nunique()
repurchase_users = (repurchase_users >= 2).sum()

# 计算各阶段流失率
stages = {
    "注册用户": total_users,
    "有购买行为": pv_users,
    "完成支付": pay_users,
    "复购用户": repurchase_users,
}

for i, (stage, cnt) in enumerate(stages.items()):
    rate = cnt / total_users * 100
    if i > 0:
        prev_name = list(stages.keys())[i - 1]
        prev_cnt = stages[prev_name]
        conv = cnt / prev_cnt * 100 if prev_cnt > 0 else 0
        print(f"  {stage}: {cnt:,} ({rate:.1f}% of total) | 上一步转化率: {conv:.1f}%")
    else:
        print(f"  {stage}: {cnt:,} ({rate:.1f}% of total)")

# 关键流失节点诊断
cart_abandon_rate = (pv_users - pay_users) / pv_users * 100 if pv_users > 0 else 0
repurchase_loss = (pay_users - repurchase_users) / pay_users * 100 if pay_users > 0 else 0
print(f"\n  关键流失点:")
print(f"    加购→支付 流失率: {cart_abandon_rate:.1f}%")
print(f"    首购→复购 流失率: {repurchase_loss:.1f}%")

# === 2. Pareto 分析 (20/80 法则) ===
print("\n" + "=" * 50)
print("【Pareto 分析 — 品类贡献度】")

# 按品类计算 GMV 占比
category_gmv = orders[orders["order_status"] != "cancelled"]\
    .groupby("category")["total_amount"].sum().sort_values(ascending=False)
total_gmv = category_gmv.sum()

category_gmv = category_gmv.reset_index()
category_gmv.columns = ["category", "gmv"]
category_gmv["share_pct"] = category_gmv["gmv"] / total_gmv * 100
category_gmv["cum_share"] = category_gmv["share_pct"].cumsum()

# ABC 分级
def abc_level(cum_share):
    if cum_share <= 80:
        return "A类-核心品类"
    elif cum_share <= 95:
        return "B类-成长品类"
    else:
        return "C类-长尾品类"

category_gmv["abc_level"] = category_gmv["cum_share"].apply(abc_level)

for _, row in category_gmv.iterrows():
    print(f"  {row['category']:20s} | ¥{row['gmv']:>12,.0f} | {row['share_pct']:5.1f}% | cum: {row['cum_share']:5.1f}% | {row['abc_level']}")

# 关键结论
a_count = (category_gmv["abc_level"] == "A类-核心品类").sum()
a_gmv = category_gmv[category_gmv["abc_level"] == "A类-核心品类"]["gmv"].sum()
print(f"\n  📌 Top {a_count} 个品类（A类）贡献了 ¥{a_gmv:,.0f} ({a_gmv/total_gmv*100:.1f}%) 的 GMV")

# === 3. 商品集中度 ===
product_gmv = orders[orders["order_status"] != "cancelled"]\
    .groupby("product_name")["total_amount"].sum().sort_values(ascending=False)
total_products = len(product_gmv)
top20_pct = int(total_products * 0.2)
top20_gmv = product_gmv.head(top20_pct).sum()
print(f"\n  商品集中度: 前 20% 商品({top20_pct}/{total_products})贡献了 {top20_gmv/total_gmv*100:.1f}% 收入")

print("\n✅ AARRR + Pareto 分析完成")
