# ============================================================
# 电商销售数据分析 — 全局配置
# ============================================================
from pathlib import Path

# 项目根目录
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# 数据路径
DATA_DIR = PROJECT_ROOT / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
PROCESSED_DIR = DATA_DIR / "processed"

# 输出路径
OUTPUT_DIR = PROJECT_ROOT / "output"
FIGURE_DIR = OUTPUT_DIR / "figures"
REPORT_DIR = OUTPUT_DIR / "reports"

# 确保目录存在
for d in [RAW_DATA_DIR, PROCESSED_DIR, FIGURE_DIR, REPORT_DIR]:
    d.mkdir(parents=True, exist_ok=True)

# MySQL 连接配置
MYSQL_CONFIG = {
    "host": "localhost",
    "port": 3306,
    "user": "root",
    "password": "",
    "database": "ecommerce_sales",
    "charset": "utf8mb4",
}

# 日期范围
ANALYSIS_START = "2022-01-01"
ANALYSIS_END = "2023-12-31"

# 可视化样式
PLOT_STYLE = {
    "figure.dpi": 150,
    "savefig.dpi": 150,
    "font.size": 11,
    "axes.titlesize": 14,
    "axes.labelsize": 12,
}
