# E-Commerce Sales & Customer Analysis

> **An end-to-end data engineering + analytics portfolio project** built on the [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) using **Oracle 21c XE**, **SQL\*Loader**, **PL/SQL**, and **Python**.

---

## Project Overview

This project ingests 9 raw CSV files (630,000+ rows), runs a full ETL pipeline from staging through a star schema, and produces 10 business-insight queries — all in a local Oracle database.

```
Raw CSV files
    │
    ▼  (SQL*Loader — Stage 2)
Staging Tables  [stg_*]         ← exact copies, VARCHAR2, no constraints
    │
    ▼  (PL/SQL procedures — Stage 3)
Clean Tables    [clean_*]       ← proper types, dedup, audit log
    │
    ▼  (PL/SQL procedures — Stage 4)
Star Schema     [dim_* / fact_*]  ← analytics-ready
    │
    ▼  (SQL queries + Python — Stage 5)
Portfolio Insights + Charts
```

---

## Dataset

| File | Table | Rows |
|---|---|---:|
| olist_order_customer_dataset.csv | stg_customers | 99,441 |
| olist_geolocation_dataset.csv | stg_geolocation | 1,000,163 |
| olist_orders_dataset.csv | stg_orders | 99,441 |
| olist_order_items_dataset.csv | stg_order_items | 112,650 |
| olist_order_payments_dataset.csv | stg_order_payments | 103,886 |
| olist_order_reviews_dataset.csv | stg_order_reviews | 99,224 |
| olist_products_dataset.csv | stg_products | 32,951 |
| olist_sellers_dataset.csv | stg_sellers | 3,095 |
| product_category_name_translation.csv | stg_category_translation | 71 |

Source: [Kaggle — Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) · License: CC BY-NC-SA 4.0

---

## Star Schema

```
         dim_date          dim_customer
            │                   │
            └────────┬──────────┘
                 fact_orders
                 (99,441 rows)
                      │
            ┌─────────┴──────────┐
       dim_seller           dim_product
            └────────┬───────────┘
              fact_order_items
              (112,650 rows)
```

| Table | Type | Grain | Rows |
|---|---|---|---:|
| dim_date | Dimension | One row per calendar date (2016–2019) | 1,461 |
| dim_customer | Dimension | One row per unique customer (person) | 96,096 |
| dim_seller | Dimension | One row per seller | 3,095 |
| dim_product | Dimension | One row per product | 32,951 |
| fact_orders | Fact | One row per order | 99,441 |
| fact_order_items | Fact | One row per line item | 112,650 |

---

## Directory Structure

```
e_commerce_sales_and_customer_analysis/
│
├── data/
│   ├── raw/            ← original CSV files (not committed to git)
│   └── prepared/       ← pre-processed reviews file
│
├── ctl/                ← SQL*Loader control files (one per table)
├── logs/               ← SQL*Loader load logs
│
├── sql/
│   ├── 03_reconcile_staging.sql
│   ├── 04_create_audit_log.sql
│   ├── 05_create_clean_tables.sql
│   ├── 06_run_cleaning.sql
│   ├── 07_create_star_schema.sql
│   ├── 08_run_star.sql
│   └── 09_analysis_queries.sql
│
├── plsql/
│   ├── clean_procedures.sql
│   └── star_procedures.sql
│
├── scripts/
│   ├── prepare_reviews.py
│   └── load_all.bat
│
├── notebooks/
│   ├── analysis.py        ← Python script / VS Code interactive cells
│   ├── analysis.ipynb     ← Jupyter notebook with pandas & matplotlib
│   └── charts/            ← 11 generated publication-ready PNG charts
│
├── docs/
│   └── powerbi_guide.md   ← Power BI connection & DAX model guide
│
├── requirements.txt
└── README.md
```

---

## How to Run

### Prerequisites
- Oracle Database 21c XE installed and running
- SQL\*Plus and SQL\*Loader on PATH
- Python 3.9+ with `pip install -r requirements.txt`

### Stage 2 — Load raw CSVs
```cmd
python scripts\prepare_reviews.py
scripts\load_all.bat
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @sql\03_reconcile_staging.sql
```

### Stage 3 — Clean the data
```cmd
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @sql\04_create_audit_log.sql
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @sql\05_create_clean_tables.sql
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @plsql\clean_procedures.sql
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @sql\06_run_cleaning.sql
```

### Stage 4 — Build the star schema
```cmd
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @sql\07_create_star_schema.sql
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @plsql\star_procedures.sql
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @sql\08_run_star.sql
```

### Stage 5 — Analysis
```cmd
sqlplus projectuser/<pwd>@localhost:1521/XEPDB1 @sql\09_analysis_queries.sql
```
```bash
set DB_PASSWORD=<your_password>
python notebooks/analysis.py
```

---

## Key Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| Staging column types | All `VARCHAR2` | Loads never fail; types converted in cleaning layer |
| Review dedup (Rule 1A) | Keep row with latest `review_answer_timestamp` | Most recent response reflects final seller state |
| Geolocation dedup (Rule 2A) | AVG lat/lng, MIN city/state per zip prefix | 261,831 duplicates → 19,015 unique zip codes |
| City standardisation (Rule 3A) | `UPPER(TRIM(city))` only | UTL_I18N not verified; documented in code |
| Null product category (Rule 4A) | → `'Unknown'`; untranslated → keep Portuguese name | Preserves all 32,951 products |
| NULL delivery date (Rule 5A) | Keep in clean table; exclude from delay calcs | 8 confirmed-delivered orders with missing timestamp |
| `DELETE + INSERT` in procedures | Not `TRUNCATE` | Atomic; rolls back on error |
| `PRAGMA AUTONOMOUS_TRANSACTION` | On `p_log_start` / `p_log_end` | Audit rows survive a ROLLBACK |
| dim_customer grain | `customer_unique_id` (person) | Required for RFM Frequency |
| Revenue definition | `SUM(price)` only — excludes freight | Freight is a cost, not product revenue |

---

## Key Findings

| Metric | Value |
|---|---|
| Total revenue (excl. cancelled, 2016–2018) | **R$ 13.49 million** |
| Avg delivery time | **12.6 days** |
| On-time delivery rate | **91.9%** |
| #1 category by revenue | Health & Beauty (R$ 1.26M) |
| Best reviewed category | Books — General Interest (avg 4.48 ★) |
| Worst reviewed category | Office Furniture (avg 3.49 ★, 21% one-star) |
| São Paulo delivery advantage | 8.8 days avg vs 20–27 days in Northeast states |
| Credit card dominance | 74% of transactions; avg 3.5 installments |
| Repeat customer premium | 3% repeat, but spend **88% more** (R$259 vs R$138) |
| Black Friday spike | November 2017 revenue **+52% MoM** |

---

## Tech Stack

| Layer | Tool |
|---|---|
| Database | Oracle Database 21c Express Edition |
| Data Loading | SQL\*Loader (sqlldr) |
| ETL / Procedures | PL/SQL (stored procedures, autonomous transactions) |
| Query Interface | SQL\*Plus |
| Python | Python 3.x · oracledb · pandas · matplotlib · seaborn |
| Version Control | Git |

---


