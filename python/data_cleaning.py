# ============================================================
# 电商销售数据分析 — Python 数据清洗脚本
# 功能: CSV 读取 / 缺失值处理 / 异常值过滤 / 类型转换
# ============================================================
import pandas as pd
import numpy as np
from pathlib import Path

# ---- 配置 ----
DATA_DIR = Path("data/raw")
OUTPUT_DIR = Path("data/processed")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# ---- 读取 ----
orders = pd.read_csv(DATA_DIR / "orders.csv")
customers = pd.read_csv(DATA_DIR / "customers.csv")
promotions = pd.read_csv(DATA_DIR / "promotions.csv")

# ---- 订单表清洗 ----
print(f"[清洗前] 订单表: {len(orders)} 行")

# 1. 去重
orders.drop_duplicates(subset="order_id", inplace=True)

# 2. 缺失值处理
orders["discount_rate"] = orders["discount_rate"].fillna(0)
orders["promotion_id"] = orders["promotion_id"].replace("", np.nan)

# 3. 异常值过滤
orders = orders[(orders["quantity"] > 0) & (orders["total_amount"] > 0)]

# 4. 日期标准化
orders["order_date"] = pd.to_datetime(orders["order_date"], errors="coerce")
orders["ship_date"] = pd.to_datetime(orders["ship_date"], errors="coerce")

# 5. 过滤明显异常的日期
valid_date_mask = orders["order_date"].notna() & (
    orders["order_date"] >= pd.Timestamp("2022-01-01")
)
orders = orders[valid_date_mask]

# 6. 衍生字段
orders["actual_amount"] = orders["total_amount"] * (1 - orders["discount_rate"])
orders["ship_interval"] = (orders["ship_date"] - orders["order_date"]).dt.days

print(f"[清洗后] 订单表: {len(orders)} 行, 缺失率: {orders.isnull().mean().round(4).to_dict()}")

# ---- 客户表清洗 ----
print(f"[清洗前] 客户表: {len(customers)} 行")
customers["register_date"] = pd.to_datetime(customers["register_date"], errors="coerce")
customers = customers[customers["register_date"].notna()]
print(f"[清洗后] 客户表: {len(customers)} 行")

# ---- 导出 ----
orders.to_csv(OUTPUT_DIR / "orders_cleaned.csv", index=False)
customers.to_csv(OUTPUT_DIR / "customers_cleaned.csv", index=False)
promotions.to_csv(OUTPUT_DIR / "promotions_cleaned.csv", index=False)

print("✅ 数据清洗完成，已导出至 data/processed/")
