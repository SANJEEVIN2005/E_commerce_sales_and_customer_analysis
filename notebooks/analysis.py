"""
E-Commerce Sales & Customer Analysis
=====================================
Dataset : Olist Brazilian E-Commerce (2016-2018)
Database: Oracle 21c XE  |  Schema: projectuser  |  PDB: XEPDB1

This script reproduces all 10 Stage-5 portfolio queries and saves
each result as a chart in the charts/ folder.

Run in VSCode  : open file -> Run Cell buttons appear next to # %%
Run in Jupyter : jupytext --to notebook notebooks/analysis.py
                 jupyter notebook notebooks/analysis.ipynb
Run as script  : python notebooks/analysis.py
"""

# %% [markdown]
# ## 0. Setup

# %%
import os
import getpass
import warnings

import oracledb
import pandas as pd
import matplotlib
try:
    get_ipython()
except NameError:
    matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
import numpy as np

warnings.filterwarnings("ignore")

# ---------- style -----------------------------------------------------------
sns.set_theme(style="whitegrid", palette="muted", font_scale=1.05)
plt.rcParams.update(
    {
        "figure.dpi": 130,
        "axes.titlesize": 13,
        "axes.titleweight": "bold",
        "axes.labelsize": 11,
        "figure.facecolor": "white",
    }
)
COLORS = sns.color_palette("muted", 12)

# Determine working directory safely in both script and notebook environments
try:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
except NameError:
    BASE_DIR = os.path.abspath(os.getcwd())
    if not os.path.basename(BASE_DIR) == "notebooks" and os.path.exists(os.path.join(BASE_DIR, "notebooks")):
        BASE_DIR = os.path.join(BASE_DIR, "notebooks")

CHART_DIR = os.path.join(BASE_DIR, "charts")
os.makedirs(CHART_DIR, exist_ok=True)


def save(fig: plt.Figure, name: str) -> None:
    path = os.path.join(CHART_DIR, f"{name}.png")
    fig.savefig(path, bbox_inches="tight")
    print(f"Saved: {name}.png")


# ---------- connect ---------------------------------------------------------
# oracledb thin mode: no Oracle Client install required.
# Reads password from DB_PASSWORD environment variable or prompts securely
DB_USER     = "projectuser"
DB_PASSWORD = os.getenv("DB_PASSWORD") or getpass.getpass("Enter Oracle password: ")
DB_DSN      = "localhost:1521/XEPDB1"

conn = oracledb.connect(user=DB_USER, password=DB_PASSWORD, dsn=DB_DSN)
print(f"Connected to Oracle {conn.version}")


def q(sql: str) -> pd.DataFrame:
    """Run SQL, return a pandas DataFrame."""
    return pd.read_sql(sql, conn)


# %% [markdown]
# ## Q1 ??? Monthly Revenue Trend

# %%
sql_q1 = """
SELECT
    d.year,
    d.month_num,
    d.month_name,
    COUNT(fo.order_id)          AS orders,
    ROUND(SUM(fo.total_revenue), 2) AS revenue
FROM fact_orders fo
JOIN dim_date d ON d.date_key = fo.purchase_date_key
WHERE fo.order_status NOT IN ('canceled','unavailable')
GROUP BY d.year, d.month_num, d.month_name
ORDER BY d.year, d.month_num
"""
df_q1 = q(sql_q1)

# Build an x-axis label like "Jan-17"
months_abbr = {
    1:"Jan",2:"Feb",3:"Mar",4:"Apr",5:"May",6:"Jun",
    7:"Jul",8:"Aug",9:"Sep",10:"Oct",11:"Nov",12:"Dec"
}
df_q1["label"] = df_q1.apply(
    lambda r: f"{months_abbr[int(r.MONTH_NUM)]}-{str(int(r.YEAR))[2:]}", axis=1
)

fig, ax = plt.subplots(figsize=(14, 5))
ax.fill_between(range(len(df_q1)), df_q1["REVENUE"] / 1_000,
                alpha=0.25, color=COLORS[0])
ax.plot(range(len(df_q1)), df_q1["REVENUE"] / 1_000,
        marker="o", markersize=4, color=COLORS[0], linewidth=2)
ax.set(
    title="Q1 ??? Monthly Revenue Trend (2016???2018)",
    xlabel="Month",
    ylabel="Revenue (R$ thousands)",
    xticks=range(len(df_q1)),
    xticklabels=df_q1["label"],
)
plt.xticks(rotation=45, ha="right")
# Annotate the peak month (November 2017)
peak_idx = df_q1["REVENUE"].idxmax()
ax.annotate(
    f"Peak\n{df_q1.loc[peak_idx,'label']}\nR${df_q1.loc[peak_idx,'REVENUE']/1000:.0f}K",
    xy=(peak_idx, df_q1.loc[peak_idx, "REVENUE"] / 1_000),
    xytext=(peak_idx - 2, df_q1.loc[peak_idx, "REVENUE"] / 1_000 + 50),
    arrowprops=dict(arrowstyle="->", color="black"),
    fontsize=9,
)
plt.tight_layout()
save(fig, "q1_monthly_revenue")
plt.show()

# %% [markdown]
# ## Q2 ??? RFM Customer Segmentation

# %%
sql_q2 = """
WITH ref AS (
    SELECT MAX(d.full_date) AS ref_date
    FROM fact_orders fo JOIN dim_date d ON d.date_key = fo.purchase_date_key
    WHERE fo.purchase_date_key IS NOT NULL
),
rfm_raw AS (
    SELECT fo.customer_key,
           MAX(d.full_date)      AS last_order_date,
           COUNT(fo.order_id)    AS frequency,
           SUM(fo.total_revenue) AS monetary
    FROM fact_orders fo
    JOIN dim_date d ON d.date_key = fo.purchase_date_key
    WHERE fo.order_status NOT IN ('canceled','unavailable')
    GROUP BY fo.customer_key
),
rfm_scored AS (
    SELECT customer_key, frequency, ROUND(monetary,2) AS monetary,
           6 - NTILE(5) OVER (ORDER BY last_order_date ASC) AS r_score,
           NTILE(5) OVER (ORDER BY frequency ASC)           AS f_score,
           NTILE(5) OVER (ORDER BY monetary   ASC)          AS m_score
    FROM rfm_raw
),
rfm_labeled AS (
    SELECT customer_key, frequency, monetary, r_score, f_score, m_score,
           CASE
               WHEN r_score>=4 AND f_score>=4 AND m_score>=4 THEN 'Champions'
               WHEN r_score>=4 AND f_score>=3               THEN 'Loyal Customers'
               WHEN r_score>=4 AND f_score<=2               THEN 'Potential Loyalists'
               WHEN r_score=3  AND f_score>=3               THEN 'At Risk'
               WHEN r_score<=2 AND f_score>=3               THEN 'Cannot Lose Them'
               WHEN r_score<=2 AND f_score<=2               THEN 'Lost'
               ELSE 'Needs Attention'
           END AS segment
    FROM rfm_scored
)
SELECT segment,
       COUNT(*)                                            AS customers,
       ROUND(COUNT(*)*100/SUM(COUNT(*)) OVER(),1)         AS pct,
       ROUND(AVG(monetary),2)                             AS avg_monetary
FROM rfm_labeled
GROUP BY segment
ORDER BY customers DESC
"""
df_q2 = q(sql_q2)

segment_colors = {
    "Champions": "#2ca02c",
    "Loyal Customers": "#1f77b4",
    "Potential Loyalists": "#17becf",
    "At Risk": "#ff7f0e",
    "Cannot Lose Them": "#d62728",
    "Needs Attention": "#9467bd",
    "Lost": "#7f7f7f",
}
colors_mapped = [segment_colors.get(s, "#aec7e8") for s in df_q2["SEGMENT"]]

fig, axes = plt.subplots(1, 2, figsize=(14, 6))

# Donut
wedges, texts, autotexts = axes[0].pie(
    df_q2["CUSTOMERS"],
    labels=df_q2["SEGMENT"],
    autopct="%1.1f%%",
    startangle=140,
    pctdistance=0.82,
    colors=colors_mapped,
    wedgeprops=dict(width=0.55),
)
axes[0].set_title("Customer Share by RFM Segment")

# Avg spend per segment
axes[1].barh(df_q2["SEGMENT"], df_q2["AVG_MONETARY"], color=colors_mapped)
axes[1].set(title="Avg Spend (R$) per Segment",
            xlabel="Avg Lifetime Value (R$)")
for i, v in enumerate(df_q2["AVG_MONETARY"]):
    axes[1].text(v + 2, i, f"R${v:.0f}", va="center", fontsize=9)

plt.suptitle("Q2 ??? RFM Customer Segmentation", fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q2_rfm_segments")
plt.show()

# %% [markdown]
# ## Q3 ??? Category Performance Dashboard

# %%
sql_q3 = """
SELECT dp.product_category_name_english       AS category,
       COUNT(DISTINCT fo.order_id)             AS orders,
       ROUND(SUM(fi.price),2)                  AS revenue,
       ROUND(AVG(fo.review_score),2)           AS avg_review,
       ROUND(AVG(fo.days_to_delivery),1)       AS avg_del_days,
       ROUND(
           SUM(CASE WHEN fo.is_late=1 THEN 1 ELSE 0 END)*100
           /NULLIF(COUNT(CASE WHEN fo.is_late IS NOT NULL THEN 1 END),0)
       ,1)                                     AS late_pct
FROM fact_order_items fi
JOIN dim_product dp ON dp.product_key = fi.product_key
JOIN fact_orders  fo ON fo.order_id   = fi.order_id
WHERE fo.order_status NOT IN ('canceled','unavailable')
GROUP BY dp.product_category_name_english
ORDER BY revenue DESC
FETCH FIRST 15 ROWS ONLY
"""
df_q3 = q(sql_q3)

fig, axes = plt.subplots(1, 2, figsize=(16, 7))

# Revenue bar (horizontal)
bars = axes[0].barh(
    df_q3["CATEGORY"][::-1], df_q3["REVENUE"][::-1] / 1_000,
    color=sns.color_palette("Blues_r", len(df_q3))
)
axes[0].set(title="Revenue by Category (Top 15)", xlabel="Revenue (R$ thousands)")
for bar, val in zip(bars, df_q3["REVENUE"][::-1] / 1_000):
    axes[0].text(val + 5, bar.get_y() + bar.get_height() / 2,
                 f"R${val:.0f}K", va="center", fontsize=8)

# Avg review score scatter
scatter = axes[1].scatter(
    df_q3["AVG_DEL_DAYS"], df_q3["AVG_REVIEW"],
    s=df_q3["ORDERS"] / 10,
    c=df_q3["LATE_PCT"], cmap="RdYlGn_r",
    alpha=0.8, edgecolors="gray", linewidths=0.5
)
axes[1].set(
    title="Review Score vs Delivery Speed\n(bubble = orders, colour = late %)",
    xlabel="Avg Delivery Days",
    ylabel="Avg Review Score (1???5)",
)
plt.colorbar(scatter, ax=axes[1], label="Late %")
for _, row in df_q3.iterrows():
    axes[1].annotate(
        row["CATEGORY"][:12],
        (row["AVG_DEL_DAYS"], row["AVG_REVIEW"]),
        fontsize=7, ha="center", va="bottom"
    )

plt.suptitle("Q3 ??? Category Performance Dashboard", fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q3_category_dashboard")
plt.show()

# %% [markdown]
# ## Q4 ??? Seller Leaderboard

# %%
sql_q4 = """
SELECT ds.seller_key                  AS seller_id,
       ds.seller_city                 AS city,
       ds.seller_state                AS state,
       COUNT(DISTINCT fi.order_id)    AS orders,
       ROUND(SUM(fi.price),2)         AS revenue,
       ROUND(AVG(fo.review_score),2)  AS avg_review,
       ROUND(AVG(fo.days_to_delivery),1) AS avg_del_days
FROM fact_order_items fi
JOIN dim_seller  ds ON ds.seller_key = fi.seller_key
JOIN fact_orders fo ON fo.order_id   = fi.order_id
WHERE fo.order_status NOT IN ('canceled','unavailable')
GROUP BY ds.seller_key, ds.seller_city, ds.seller_state
ORDER BY revenue DESC
FETCH FIRST 10 ROWS ONLY
"""
df_q4 = q(sql_q4)
df_q4["label"] = df_q4["CITY"] + "\n(" + df_q4["STATE"] + ")"
df_q4["seller_short"] = df_q4["SELLER_ID"].str[:8] + "???"

fig, axes = plt.subplots(1, 2, figsize=(15, 5))

# Revenue bar
bar_colors = [COLORS[0] if s == "SP" else COLORS[1] for s in df_q4["STATE"]]
axes[0].bar(range(len(df_q4)), df_q4["REVENUE"] / 1_000, color=bar_colors)
axes[0].set(
    title="Top 10 Sellers by Revenue",
    xlabel="Seller", ylabel="Revenue (R$ thousands)",
    xticks=range(len(df_q4)), xticklabels=df_q4["seller_short"]
)
plt.setp(axes[0].get_xticklabels(), rotation=30, ha="right", fontsize=8)

# Review score
axes[1].bar(range(len(df_q4)), df_q4["AVG_REVIEW"],
            color=[plt.cm.RdYlGn(r / 5) for r in df_q4["AVG_REVIEW"]])
axes[1].axhline(df_q4["AVG_REVIEW"].mean(), color="red",
                linestyle="--", linewidth=1, label="Mean")
axes[1].set(
    title="Avg Review Score ??? Top 10 Sellers",
    xlabel="Seller", ylabel="Avg Review (1???5)",
    ylim=(2.5, 5),
    xticks=range(len(df_q4)), xticklabels=df_q4["seller_short"]
)
plt.setp(axes[1].get_xticklabels(), rotation=30, ha="right", fontsize=8)
axes[1].legend()

plt.suptitle("Q4 ??? Seller Leaderboard", fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q4_seller_leaderboard")
plt.show()

# %% [markdown]
# ## Q5 ??? State Performance

# %%
sql_q5 = """
SELECT dc.customer_state                        AS state,
       COUNT(fo.order_id)                       AS orders,
       ROUND(SUM(fo.total_revenue),2)           AS revenue,
       ROUND(AVG(fo.days_to_delivery),1)        AS avg_del_days,
       ROUND(SUM(fo.is_late)*100
             /NULLIF(COUNT(CASE WHEN fo.is_late IS NOT NULL THEN 1 END),0),1) AS late_pct,
       ROUND(AVG(fo.review_score),2)            AS avg_review
FROM fact_orders fo
JOIN dim_customer dc ON dc.customer_key = fo.customer_key
WHERE fo.order_status NOT IN ('canceled','unavailable')
GROUP BY dc.customer_state
ORDER BY orders DESC
"""
df_q5 = q(sql_q5)
top10 = df_q5.head(10)

fig, axes = plt.subplots(1, 3, figsize=(18, 5))

# Orders
axes[0].barh(top10["STATE"][::-1], top10["ORDERS"][::-1],
             color=COLORS[0])
axes[0].set(title="Orders by State (Top 10)", xlabel="Orders")

# Avg delivery days
cmap_vals = (top10["AVG_DEL_DAYS"] - top10["AVG_DEL_DAYS"].min()) / \
            (top10["AVG_DEL_DAYS"].max() - top10["AVG_DEL_DAYS"].min())
del_colors = [plt.cm.RdYlGn_r(v) for v in cmap_vals]
bars = axes[1].barh(top10["STATE"][::-1], top10["AVG_DEL_DAYS"][::-1],
                    color=del_colors[::-1])
axes[1].set(title="Avg Delivery Days by State", xlabel="Days")
for bar, val in zip(bars, top10["AVG_DEL_DAYS"][::-1]):
    axes[1].text(val + 0.2, bar.get_y() + bar.get_height() / 2,
                 f"{val:.1f}d", va="center", fontsize=9)

# Late %
axes[2].barh(top10["STATE"][::-1], top10["LATE_PCT"][::-1],
             color=[plt.cm.Reds(v / 25) for v in top10["LATE_PCT"][::-1]])
axes[2].set(title="Late Delivery % by State", xlabel="Late %")
for bar, val in zip(axes[2].patches, top10["LATE_PCT"][::-1]):
    axes[2].text(val + 0.2, bar.get_y() + bar.get_height() / 2,
                 f"{val:.1f}%", va="center", fontsize=9)

plt.suptitle("Q5 ??? State Performance (Top 10 States by Orders)",
             fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q5_state_performance")
plt.show()

# %% [markdown]
# ## Q6 ??? Payment Method Analysis

# %%
sql_q6 = """
SELECT payment_type,
       COUNT(*)                                          AS payment_rows,
       ROUND(SUM(payment_value),2)                      AS total_paid,
       ROUND(AVG(payment_installments),1)               AS avg_installments,
       ROUND(AVG(payment_value),2)                      AS avg_value
FROM clean_order_payments
WHERE payment_type IS NOT NULL
  AND payment_type != 'not_defined'
GROUP BY payment_type
ORDER BY payment_rows DESC
"""
df_q6 = q(sql_q6)

fig, axes = plt.subplots(1, 3, figsize=(16, 5))

# Donut ??? share of transactions
wedge_colors = [COLORS[i] for i in range(len(df_q6))]
axes[0].pie(
    df_q6["PAYMENT_ROWS"],
    labels=df_q6["PAYMENT_TYPE"],
    autopct="%1.1f%%",
    startangle=90,
    colors=wedge_colors,
    wedgeprops=dict(width=0.55),
    pctdistance=0.82,
)
axes[0].set_title("Transaction Share by Payment Type")

# Total paid bar
axes[1].bar(df_q6["PAYMENT_TYPE"], df_q6["TOTAL_PAID"] / 1_000_000,
            color=wedge_colors)
axes[1].set(title="Total Paid (R$ millions)", ylabel="R$ millions")

# Avg installments
axes[2].bar(df_q6["PAYMENT_TYPE"], df_q6["AVG_INSTALLMENTS"],
            color=wedge_colors)
axes[2].axhline(1, color="red", linestyle="--", linewidth=0.8)
axes[2].set(title="Avg Installments", ylabel="Installments")
for i, val in enumerate(df_q6["AVG_INSTALLMENTS"]):
    axes[2].text(i, val + 0.05, f"{val:.1f}x", ha="center", fontsize=10)

plt.suptitle("Q6 ??? Payment Method Analysis", fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q6_payment_methods")
plt.show()

# %% [markdown]
# ## Q7 ??? Review Score by Category (Best & Worst)

# %%
sql_q7 = """
SELECT dp.product_category_name_english              AS category,
       COUNT(fo.review_score)                        AS reviews,
       ROUND(AVG(fo.review_score),2)                 AS avg_score,
       ROUND(SUM(CASE WHEN fo.review_score=5 THEN 1 ELSE 0 END)*100
             /NULLIF(COUNT(fo.review_score),0),1)    AS pct_5star,
       ROUND(SUM(CASE WHEN fo.review_score=1 THEN 1 ELSE 0 END)*100
             /NULLIF(COUNT(fo.review_score),0),1)    AS pct_1star
FROM fact_order_items fi
JOIN dim_product dp ON dp.product_key = fi.product_key
JOIN fact_orders  fo ON fo.order_id   = fi.order_id
WHERE fo.review_score IS NOT NULL
  AND fo.order_status NOT IN ('canceled','unavailable')
GROUP BY dp.product_category_name_english
HAVING COUNT(fo.review_score) >= 100
ORDER BY avg_score DESC
"""
df_q7 = q(sql_q7)
best   = df_q7.head(10)
worst  = df_q7.tail(10).sort_values("AVG_SCORE")

fig, axes = plt.subplots(1, 2, figsize=(16, 6))

# Best
axes[0].barh(best["CATEGORY"][::-1], best["AVG_SCORE"][::-1],
             color=sns.color_palette("Greens_r", 10))
axes[0].set(title="Best Rated Categories (avg ??? top 10)",
            xlabel="Avg Review Score", xlim=(3, 5))
for i, (score, pct) in enumerate(zip(best["AVG_SCORE"][::-1],
                                      best["PCT_5STAR"][::-1])):
    axes[0].text(score + 0.01, i, f"{score} ({pct:.0f}% ???5)",
                 va="center", fontsize=8)

# Worst
axes[1].barh(worst["CATEGORY"], worst["AVG_SCORE"],
             color=sns.color_palette("Reds_r", 10))
axes[1].set(title="Worst Rated Categories (min 100 reviews)",
            xlabel="Avg Review Score", xlim=(2.5, 4.5))
for i, (score, pct) in enumerate(zip(worst["AVG_SCORE"],
                                      worst["PCT_1STAR"])):
    axes[1].text(score + 0.01, i, f"{score} ({pct:.0f}% ???1)",
                 va="center", fontsize=8)

plt.suptitle("Q7 ??? Review Score by Category", fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q7_review_scores")
plt.show()

# %% [markdown]
# ## Q8 ??? Peak Shopping Day of Week

# %%
sql_q8 = """
SELECT d.day_of_week, d.day_name,
       COUNT(fo.order_id)                              AS orders,
       ROUND(COUNT(fo.order_id)*100
             /SUM(COUNT(fo.order_id)) OVER(),1)        AS pct_orders,
       ROUND(AVG(fo.total_revenue),2)                  AS avg_order_value
FROM fact_orders fo
JOIN dim_date d ON d.date_key = fo.purchase_date_key
WHERE fo.order_status NOT IN ('canceled','unavailable')
GROUP BY d.day_of_week, d.day_name
ORDER BY d.day_of_week
"""
df_q8 = q(sql_q8)

weekend_mask = df_q8["DAY_OF_WEEK"].isin([1, 7])
bar_colors   = ["#d62728" if w else COLORS[0] for w in weekend_mask]

fig, axes = plt.subplots(1, 2, figsize=(14, 5))

bars = axes[0].bar(df_q8["DAY_NAME"], df_q8["ORDERS"] / 1_000,
                   color=bar_colors)
axes[0].set(title="Orders by Day of Week\n(red = weekend)",
            xlabel="Day", ylabel="Orders (thousands)")
for bar, pct in zip(bars, df_q8["PCT_ORDERS"]):
    axes[0].text(bar.get_x() + bar.get_width() / 2,
                 bar.get_height() + 0.1,
                 f"{pct:.1f}%", ha="center", fontsize=9)

axes[1].bar(df_q8["DAY_NAME"], df_q8["AVG_ORDER_VALUE"],
            color=bar_colors)
axes[1].set(title="Avg Order Value by Day",
            xlabel="Day", ylabel="Avg Revenue (R$)")
axes[1].axhline(df_q8["AVG_ORDER_VALUE"].mean(), color="navy",
                linestyle="--", linewidth=1, label="Overall avg")
axes[1].legend()

plt.suptitle("Q8 ??? Peak Shopping Day of Week", fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q8_day_of_week")
plt.show()

# %% [markdown]
# ## Q9 ??? Delivery Speed Distribution

# %%
sql_q9 = """
SELECT
    CASE
        WHEN days_to_delivery < 7  THEN '< 7 days'
        WHEN days_to_delivery < 14 THEN '7-13 days'
        WHEN days_to_delivery < 21 THEN '14-20 days'
        WHEN days_to_delivery < 30 THEN '21-29 days'
        ELSE '30+ days'
    END AS delivery_bucket,
    COUNT(*)                                             AS orders,
    ROUND(COUNT(*)*100/SUM(COUNT(*)) OVER(),1)           AS pct
FROM fact_orders
WHERE order_status = 'delivered'
  AND days_to_delivery IS NOT NULL
GROUP BY
    CASE
        WHEN days_to_delivery < 7  THEN '< 7 days'
        WHEN days_to_delivery < 14 THEN '7-13 days'
        WHEN days_to_delivery < 21 THEN '14-20 days'
        WHEN days_to_delivery < 30 THEN '21-29 days'
        ELSE '30+ days'
    END
ORDER BY MIN(days_to_delivery)
"""
df_q9 = q(sql_q9)

bucket_colors = ["#2ca02c", "#98df8a", "#ffbb78", "#ff7f0e", "#d62728"]

fig, axes = plt.subplots(1, 2, figsize=(14, 5))

# Bar
bars = axes[0].bar(df_q9["DELIVERY_BUCKET"], df_q9["ORDERS"] / 1_000,
                   color=bucket_colors)
axes[0].set(title="Delivery Speed Distribution",
            xlabel="Delivery Bucket", ylabel="Orders (thousands)")
for bar, pct in zip(bars, df_q9["PCT"]):
    axes[0].text(bar.get_x() + bar.get_width() / 2,
                 bar.get_height() + 0.2,
                 f"{pct:.1f}%", ha="center", fontsize=10, fontweight="bold")

# Donut
axes[1].pie(
    df_q9["ORDERS"],
    labels=df_q9["DELIVERY_BUCKET"],
    autopct="%1.1f%%",
    colors=bucket_colors,
    startangle=90,
    wedgeprops=dict(width=0.55),
    pctdistance=0.82,
)
axes[1].set_title("Share of Deliveries by Speed")

plt.suptitle("Q9 ??? Delivery Speed Distribution", fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q9_delivery_speed")
plt.show()

# %% [markdown]
# ## Q10 ??? Repeat vs First-Time Customer Loyalty

# %%
sql_q10 = """
WITH customer_summary AS (
    SELECT fo.customer_key,
           COUNT(fo.order_id)    AS order_count,
           SUM(fo.total_revenue) AS total_spent
    FROM fact_orders fo
    WHERE fo.order_status NOT IN ('canceled','unavailable')
      AND fo.purchase_date_key IS NOT NULL
    GROUP BY fo.customer_key
)
SELECT CASE WHEN order_count=1 THEN 'First-Time' ELSE 'Repeat' END AS customer_type,
       COUNT(*)                                                       AS customers,
       ROUND(COUNT(*)*100/SUM(COUNT(*)) OVER(),1)                    AS pct_customers,
       SUM(order_count)                                               AS total_orders,
       ROUND(AVG(total_spent),2)                                      AS avg_ltv
FROM customer_summary
GROUP BY CASE WHEN order_count=1 THEN 'First-Time' ELSE 'Repeat' END
ORDER BY customers DESC
"""
df_q10 = q(sql_q10)

fig, axes = plt.subplots(1, 2, figsize=(13, 5))

type_colors = {"First-Time": COLORS[0], "Repeat": "#2ca02c"}
colors_list = [type_colors[t] for t in df_q10["CUSTOMER_TYPE"]]

# Customer share
axes[0].pie(
    df_q10["CUSTOMERS"],
    labels=[f"{t}\n{p:.1f}%"
            for t, p in zip(df_q10["CUSTOMER_TYPE"], df_q10["PCT_CUSTOMERS"])],
    colors=colors_list,
    startangle=90,
    wedgeprops=dict(width=0.55),
)
axes[0].set_title("Customer Share")

# Avg LTV comparison
bar_vals = df_q10["AVG_LTV"].values
bars = axes[1].bar(df_q10["CUSTOMER_TYPE"], bar_vals, color=colors_list,
                   width=0.4)
axes[1].set(title="Avg Lifetime Value (R$)",
            ylabel="Avg Total Spend (R$)", ylim=(0, bar_vals.max() * 1.25))
for bar, val in zip(bars, bar_vals):
    axes[1].text(bar.get_x() + bar.get_width() / 2,
                 bar.get_height() + 3,
                 f"R${val:.2f}", ha="center", fontsize=12, fontweight="bold")

# Annotate the uplift
uplift = (df_q10.loc[df_q10["CUSTOMER_TYPE"] == "Repeat", "AVG_LTV"].values[0] /
          df_q10.loc[df_q10["CUSTOMER_TYPE"] == "First-Time", "AVG_LTV"].values[0] - 1) * 100
axes[1].annotate(
    f"Repeat customers spend\n{uplift:.0f}% more than first-time",
    xy=(1, bar_vals.max()), xytext=(0.5, bar_vals.max() * 1.1),
    ha="center", fontsize=10, color="#2ca02c", fontweight="bold"
)

plt.suptitle("Q10 ??? Repeat vs First-Time Customer Loyalty",
             fontsize=14, fontweight="bold")
plt.tight_layout()
save(fig, "q10_customer_loyalty")
plt.show()

# %% [markdown]
# ## Summary Dashboard ??? 4 Key Metrics in One View

# %%
fig = plt.figure(figsize=(16, 10))
fig.suptitle(
    "E-Commerce Sales & Customer Analysis ??? Summary Dashboard\n"
    "Olist Brazilian Dataset | 2016???2018 | 99,441 Orders",
    fontsize=15, fontweight="bold", y=0.99
)

gs = fig.add_gridspec(2, 3, hspace=0.45, wspace=0.4)

# -- Monthly revenue (top-left, wide) --------------------------------------
ax1 = fig.add_subplot(gs[0, :2])
ax1.fill_between(range(len(df_q1)), df_q1["REVENUE"] / 1_000,
                 alpha=0.3, color=COLORS[0])
ax1.plot(range(len(df_q1)), df_q1["REVENUE"] / 1_000,
         color=COLORS[0], linewidth=2)
ax1.set(title="Monthly Revenue (R$ thousands)", xticks=range(len(df_q1)),
        xticklabels=df_q1["label"])
plt.setp(ax1.get_xticklabels(), rotation=45, ha="right", fontsize=7)

# -- Payment donut (top-right) ---------------------------------------------
ax2 = fig.add_subplot(gs[0, 2])
ax2.pie(df_q6["PAYMENT_ROWS"],
        labels=df_q6["PAYMENT_TYPE"],
        autopct="%1.0f%%",
        colors=[COLORS[i] for i in range(len(df_q6))],
        wedgeprops=dict(width=0.5), pctdistance=0.82,
        textprops=dict(fontsize=8))
ax2.set_title("Payment Mix")

# -- Top 8 categories (bottom-left) ----------------------------------------
ax3 = fig.add_subplot(gs[1, :2])
top8 = df_q3.head(8)
ax3.barh(top8["CATEGORY"][::-1], top8["REVENUE"][::-1] / 1_000,
         color=sns.color_palette("Blues_r", 8))
ax3.set(title="Top 8 Categories ??? Revenue (R$ thousands)",
        xlabel="R$ thousands")

# -- Delivery speed (bottom-right) -----------------------------------------
ax4 = fig.add_subplot(gs[1, 2])
ax4.pie(df_q9["ORDERS"], labels=df_q9["DELIVERY_BUCKET"],
        autopct="%1.0f%%", colors=bucket_colors,
        wedgeprops=dict(width=0.5), pctdistance=0.82,
        textprops=dict(fontsize=8))
ax4.set_title("Delivery Speed Mix")

save(fig, "summary_dashboard")
plt.show()

# %%
conn.close()
print("\nAll charts saved to:", os.path.abspath(CHART_DIR))
print("Done")


