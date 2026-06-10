# ============================================================
# 电商销售数据分析 — 可视化
# 功能: 月度趋势线 / 品类排行 / 区域分布 / 留存热力图
# ============================================================
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
from pathlib import Path

# ---- 中文字体设置 ----
plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "PingFang SC"]
plt.rcParams["axes.unicode_minus"] = False
sns.set_style("whitegrid")

INPUT_DIR = Path("data/processed")
OUTPUT_DIR = Path("output/figures")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

orders = pd.read_csv(INPUT_DIR / "orders_cleaned.csv", parse_dates=["order_date", "ship_date"])
customers = pd.read_csv(INPUT_DIR / "customers_cleaned.csv", parse_dates=["register_date"])

# === 图1: 月度 GMV 趋势 ===
fig, ax = plt.subplots(figsize=(12, 5))
orders["year_month"] = orders["order_date"].dt.to_period("M")
monthly = orders.groupby("year_month").agg(
    gmv=("total_amount", "sum"),
    orders=("order_id", "nunique")
).reset_index()
monthly["year_month"] = monthly["year_month"].astype(str)

ax.plot(monthly["year_month"], monthly["gmv"] / 10000, marker="o", linewidth=2, color="#2c6fce")
ax.set_title("月度 GMV 趋势", fontsize=14, fontweight="bold")
ax.set_ylabel("GMV (万元)")
ax.tick_params(axis="x", rotation=45)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "01_monthly_gmv_trend.png", dpi=150, bbox_inches="tight")
plt.close()
print("✅ 图1 已生成")

# === 图2: 品类 GMV 横向条形图 ===
fig, ax = plt.subplots(figsize=(10, 6))
cat_gmv = orders[orders["order_status"] != "cancelled"]\
    .groupby("category")["total_amount"].sum().sort_values(ascending=True)
bars = ax.barh(cat_gmv.index, cat_gmv.values / 10000, color="#2c6fce")
ax.set_title("各品类 GMV 分布", fontsize=14, fontweight="bold")
ax.set_xlabel("GMV (万元)")
for bar, val in zip(bars, cat_gmv.values / 10000):
    ax.text(bar.get_width() + 0.5, bar.get_y() + bar.get_height()/2, f"{val:.0f}", va="center", fontsize=9)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "02_category_gmv.png", dpi=150, bbox_inches="tight")
plt.close()
print("✅ 图2 已生成")

# === 图3: AARRR 漏斗图 ===
fig, ax = plt.subplots(figsize=(10, 6))
total_users = len(customers)
pv_users = orders["customer_id"].nunique()
pay_users = orders[orders["order_status"].isin(["paid", "shipped", "returned"])]["customer_id"].nunique()
repurchase = (orders[orders["order_status"].isin(["paid", "shipped", "returned"])]
              .groupby("customer_id")["order_id"].nunique() >= 2).sum()

stages = ["注册用户", "有购买行为", "完成支付", "复购用户"]
values = [total_users, pv_users, pay_users, repurchase]

# 标准化为百分比
max_val = max(values)
scaled = [v / max_val * 100 for v in values]

colors = ["#4472C4", "#5B9BD5", "#70AD47", "#FFC000"]
for i, (stage, val, s) in enumerate(zip(stages, values, scaled)):
    ax.barh(stage, s, color=colors[i], alpha=0.85, height=0.5)
    ax.text(s + 1, stage, f"{val:,} ({val/total_users*100:.1f}%)", va="center", fontsize=11)

    # 转化率标注
    if i > 0:
        conv = values[i] / values[i - 1] * 100
        loss = 100 - conv
        ax.text(50, (i - 0.5) * 1.2 - 0.15, f"流失 {loss:.1f}%", fontsize=9,
                color="#c0392b", ha="center")

ax.set_title("AARRR 用户生命周期漏斗", fontsize=14, fontweight="bold")
ax.set_xlim(0, 120)
ax.set_xlabel("用户占比 (%)")
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "03_aarrr_funnel.png", dpi=150, bbox_inches="tight")
plt.close()
print("✅ 图3 已生成")

# === 图4: 区域分布饼图 ===
fig, ax = plt.subplots(figsize=(9, 7))
region = orders.merge(customers[["customer_id", "region"]], on="customer_id", how="left")
region_gmv = region.groupby("region")["total_amount"].sum().sort_values(ascending=False)
wedges, texts, autotexts = ax.pie(
    region_gmv.values, labels=region_gmv.index, autopct="%1.1f%%",
    startangle=90, colors=sns.color_palette("Blues_r", len(region_gmv)),
    explode=[0.03] * len(region_gmv)
)
ax.set_title("区域 GMV 分布", fontsize=14, fontweight="bold")
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "04_region_distribution.png", dpi=150, bbox_inches="tight")
plt.close()
print("✅ 图4 已生成")

# === 图5: 价格带 vs 销量 ===
fig, axes = plt.subplots(1, 2, figsize=(14, 5))

# 价格区间分布
axes[0].hist(orders["unit_price"].clip(upper=500), bins=40, color="#2c6fce", alpha=0.8, edgecolor="white")
axes[0].set_title("商品单价分布", fontsize=13, fontweight="bold")
axes[0].set_xlabel("单价 (元)")
axes[0].set_ylabel("订单数")
axes[0].axvline(orders["unit_price"].median(), color="#e74c3c", linestyle="--", label=f'中位数: ¥{orders["unit_price"].median():.0f}')
axes[0].legend()

# 客单价分布
avg_order = orders.groupby("order_id")["total_amount"].sum()
axes[1].hist(avg_order.clip(upper=1000), bins=50, color="#27ae60", alpha=0.8, edgecolor="white")
axes[1].set_title("客单价分布", fontsize=13, fontweight="bold")
axes[1].set_xlabel("客单价 (元)")
axes[1].set_ylabel("订单数")
axes[1].axvline(avg_order.median(), color="#e74c3c", linestyle="--", label=f'中位数: ¥{avg_order.median():.0f}')
axes[1].legend()

plt.tight_layout()
plt.savefig(OUTPUT_DIR / "05_price_distribution.png", dpi=150, bbox_inches="tight")
plt.close()
print("✅ 图5 已生成")

print("\n✅ 全部可视化图表已保存至 output/figures/")
