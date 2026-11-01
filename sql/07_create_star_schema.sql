-- ============================================================
-- sql/07_create_star_schema.sql
-- Stage 4 Step 1: Create the star schema (4 dims + 2 facts).
--
-- HOW TO RUN:
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @sql\07_create_star_schema.sql
--
-- STAR SCHEMA OVERVIEW
-- â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
-- â”‚  dim_date   â”‚   â”‚ dim_customer â”‚   â”‚  dim_seller â”‚   â”‚ dim_product â”‚
-- â””â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”˜
--        â”‚                 â”‚                   â”‚                  â”‚
--        â””â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”˜                   â”‚                  â”‚
--           fact_orders              â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
--                                   â”‚
--                            fact_order_items
--
-- WHY TWO FACT TABLES? (explain in interviews)
--   fact_orders  = one row per ORDER.  Good for: delivery time,
--                  order status, customer behaviour, review scores.
--   fact_order_items = one row per ITEM (order x product x seller).
--                  Good for: revenue by category, seller performance.
--   Keeping them separate avoids double-counting: if you SUM revenue
--   in fact_orders you get the correct total; if you GROUP BY category
--   you use fact_order_items. Mixing both grains in one table is a
--   classic data warehouse mistake.
--
-- WHY NO FOREIGN KEYS?
--   We add FKs as DISABLE VALIDATE so Oracle documents the relationships
--   without enforcing them at insert time. This is the standard DW pattern:
--   the ETL already ensures referential integrity; the FK metadata helps
--   BI tools (like Power BI) auto-detect joins.
-- ============================================================

-- ---- Drop facts first (they reference dims), then dims ------
BEGIN EXECUTE IMMEDIATE 'DROP TABLE fact_order_items PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE fact_orders PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dim_date PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dim_customer PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dim_seller PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE dim_product PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

-- ============================================================
-- DIMENSION 1: dim_date
-- Grain: one row per calendar date, 2016-01-01 to 2019-12-31.
-- date_key = YYYYMMDD integer (e.g. 20170401).
--   Why integer, not DATE? BI tools like Power BI and Tableau
--   join on integer keys much faster than DATE comparisons.
-- is_weekend: 1 = Saturday/Sunday, 0 = weekday.
-- day_of_week: Oracle TO_CHAR(d,'D') = 1 (Sunday) to 7 (Saturday).
-- ============================================================
CREATE TABLE dim_date (
    date_key      NUMBER(8)    NOT NULL,
    full_date     DATE         NOT NULL,
    year          NUMBER(4),
    quarter       NUMBER(1),
    month_num     NUMBER(2),
    month_name    VARCHAR2(12),
    day_of_month  NUMBER(2),
    day_of_week   NUMBER(1),   -- 1=Sun, 2=Mon ... 7=Sat
    day_name      VARCHAR2(12),
    is_weekend    NUMBER(1),   -- 1=weekend, 0=weekday
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key)
);

-- ============================================================
-- DIMENSION 2: dim_customer
-- Grain: one row per UNIQUE CUSTOMER (customer_unique_id).
--   Why customer_unique_id and not customer_id?
--   In this dataset, the same person gets a new customer_id for
--   every order they place. customer_unique_id is the true person.
--   We need it to count how many orders a customer has placed
--   (Frequency in RFM analysis).
-- Source: clean_customers (deduplicated to unique persons).
-- ============================================================
CREATE TABLE dim_customer (
    customer_key             VARCHAR2(50)  NOT NULL,  -- = customer_unique_id
    customer_zip_code_prefix VARCHAR2(10),
    customer_city            VARCHAR2(100),
    customer_state           VARCHAR2(5),
    CONSTRAINT pk_dim_customer PRIMARY KEY (customer_key)
);

-- ============================================================
-- DIMENSION 3: dim_seller
-- Grain: one row per seller.
-- ============================================================
CREATE TABLE dim_seller (
    seller_key              VARCHAR2(50)  NOT NULL,  -- = seller_id
    seller_zip_code_prefix  VARCHAR2(10),
    seller_city             VARCHAR2(100),
    seller_state            VARCHAR2(5),
    CONSTRAINT pk_dim_seller PRIMARY KEY (seller_key)
);

-- ============================================================
-- DIMENSION 4: dim_product
-- Grain: one row per product.
-- Both Portuguese and English category names are kept for
-- flexibility (some BI reports may want the original label).
-- ============================================================
CREATE TABLE dim_product (
    product_key                   VARCHAR2(50)  NOT NULL,  -- = product_id
    product_category_name         VARCHAR2(100),
    product_category_name_english VARCHAR2(100),
    product_weight_g              NUMBER(10),
    product_photos_qty            NUMBER(3),
    CONSTRAINT pk_dim_product PRIMARY KEY (product_key)
);

-- ============================================================
-- FACT 1: fact_orders
-- Grain: one row per ORDER.
-- Pre-computed measures (loaded at ETL time, not at query time):
--   total_revenue    = SUM(price)          from clean_order_items
--   freight_total    = SUM(freight_value)  from clean_order_items
--   item_count       = COUNT(order_item_id)from clean_order_items
--   total_payment    = SUM(payment_value)  from clean_order_payments
--   review_score     = score               from clean_order_reviews
--   days_to_delivery = delivered - purchased (decimal days)
--   is_late          = 1 if delivered > estimated; 0 if on time;
--                      NULL if order not yet delivered
-- Rule 5A: 8 delivered orders with NULL delivery date have
--   days_to_delivery = NULL and is_late = NULL.
-- ============================================================
CREATE TABLE fact_orders (
    order_id          VARCHAR2(50)  NOT NULL,
    customer_key      VARCHAR2(50),               -- FK â†’ dim_customer
    purchase_date_key NUMBER(8),                  -- FK â†’ dim_date
    order_status      VARCHAR2(20),
    item_count        NUMBER(5),
    total_revenue     NUMBER(14,2),               -- SUM(price); excludes freight
    freight_total     NUMBER(14,2),
    total_payment     NUMBER(14,2),
    review_score      NUMBER(1),                  -- 1-5; NULL if no review
    days_to_delivery  NUMBER(8,2),                -- NULL if not delivered yet
    is_late           NUMBER(1),                  -- 1/0/NULL
    CONSTRAINT pk_fact_orders PRIMARY KEY (order_id)
);

-- ============================================================
-- FACT 2: fact_order_items
-- Grain: one row per LINE ITEM (order Ã— item sequence).
-- Used for revenue by product / category / seller analysis.
-- ship_date_key: the shipping limit date as YYYYMMDD (integer FK).
-- ============================================================
CREATE TABLE fact_order_items (
    order_id        VARCHAR2(50)  NOT NULL,
    order_item_id   NUMBER(5)     NOT NULL,
    product_key     VARCHAR2(50),               -- FK â†’ dim_product
    seller_key      VARCHAR2(50),               -- FK â†’ dim_seller
    ship_date_key   NUMBER(8),                  -- FK â†’ dim_date
    price           NUMBER(12,2),
    freight_value   NUMBER(12,2),
    CONSTRAINT pk_fact_order_items PRIMARY KEY (order_id, order_item_id)
);

