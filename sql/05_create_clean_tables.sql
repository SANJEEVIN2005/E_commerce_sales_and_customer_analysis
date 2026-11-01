-- ============================================================
-- sql/05_create_clean_tables.sql
-- Stage 3 Step 2: Create 9 clean_* tables with proper data types.
--
-- HOW TO RUN:
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @sql\05_create_clean_tables.sql
--
-- DESIGN DECISIONS (explain these in interviews)
-- * Staging tables: ALL columns are VARCHAR2, no constraints.
--     Reason: loading must never fail. We accept any raw text.
-- * Clean tables: proper types (NUMBER, TIMESTAMP), PRIMARY KEYs.
--     Reason: the cleaning procedures enforce quality here.
-- * No FOREIGN KEYS yet. They are added in Stage 4 (star schema)
--     after we confirm all clean data is consistent.
-- * Zip code prefix columns stay VARCHAR2 (not NUMBER).
--     Reason: leading zeros matter (e.g. "01310" must not become 1310).
-- * clean_order_reviews PRIMARY KEY is order_id, not review_id.
--     Reason: we deduplicate to one row per order, so order_id is unique.
--     review_id is kept for traceability but is NOT the key.
-- ============================================================

-- ---- Drop all clean tables (ignore ORA-00942 if they don't exist yet) ----
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_category_translation PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_customers PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_geolocation PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_order_items PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_order_payments PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_order_reviews PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_orders PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_products PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE clean_sellers PURGE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;
/

-- ============================================================
-- 1. clean_category_translation (71 rows expected)
-- ============================================================
CREATE TABLE clean_category_translation (
    product_category_name         VARCHAR2(100) NOT NULL,
    product_category_name_english VARCHAR2(100),
    CONSTRAINT pk_clean_cat_trans PRIMARY KEY (product_category_name)
);

-- ============================================================
-- 2. clean_customers (99,441 rows expected)
-- customer_id   : one row per order (not per person)
-- customer_unique_id : the person identifier -- use this for RFM
-- ============================================================
CREATE TABLE clean_customers (
    customer_id              VARCHAR2(50)  NOT NULL,
    customer_unique_id       VARCHAR2(50)  NOT NULL,
    customer_zip_code_prefix VARCHAR2(10),          -- text: leading zeros preserved
    customer_city            VARCHAR2(100),          -- UPPER TRIM applied
    customer_state           VARCHAR2(5),            -- 2-letter state code e.g. SP
    CONSTRAINT pk_clean_customers PRIMARY KEY (customer_id)
);

-- ============================================================
-- 3. clean_geolocation (â‰ˆ19,015 rows expected after dedup)
-- One row per zip prefix. lat/lng are the average of all raw rows
-- for that prefix (Rule 2A).
-- ============================================================
CREATE TABLE clean_geolocation (
    geolocation_zip_code_prefix VARCHAR2(10)  NOT NULL,
    geolocation_lat             NUMBER(10,6),
    geolocation_lng             NUMBER(10,6),
    geolocation_city            VARCHAR2(100),
    geolocation_state           VARCHAR2(5),
    CONSTRAINT pk_clean_geolocation PRIMARY KEY (geolocation_zip_code_prefix)
);

-- ============================================================
-- 4. clean_order_items (112,650 rows expected)
-- Composite PK: (order_id, order_item_id) because one order
-- can have multiple items numbered 1, 2, 3 ...
-- ============================================================
CREATE TABLE clean_order_items (
    order_id            VARCHAR2(50) NOT NULL,
    order_item_id       NUMBER(5)    NOT NULL,  -- item sequence within order
    product_id          VARCHAR2(50),
    seller_id           VARCHAR2(50),
    shipping_limit_date TIMESTAMP,
    price               NUMBER(12,2),           -- item price in BRL
    freight_value       NUMBER(12,2),           -- freight for this item in BRL
    CONSTRAINT pk_clean_order_items PRIMARY KEY (order_id, order_item_id)
);

-- ============================================================
-- 5. clean_order_payments (103,886 rows expected)
-- Composite PK: (order_id, payment_sequential) because one order
-- can be paid in multiple installments or payment types.
-- Payments are a separate fact table to avoid double counting
-- when joined with order_items (discussed in brief section 4).
-- ============================================================
CREATE TABLE clean_order_payments (
    order_id             VARCHAR2(50) NOT NULL,
    payment_sequential   NUMBER(3)    NOT NULL,   -- 1 = first payment row for the order
    payment_type         VARCHAR2(30),             -- credit_card | boleto | voucher | debit_card
    payment_installments NUMBER(3),
    payment_value        NUMBER(12,2),
    CONSTRAINT pk_clean_order_payments PRIMARY KEY (order_id, payment_sequential)
);

-- ============================================================
-- 6. clean_order_reviews (â‰¤99,224 rows; reduced by dedup)
-- PRIMARY KEY is order_id (not review_id) because dedup gives
-- one row per order. review_id is kept for audit traceability.
-- Rule 1A: keep the row with the latest review_answer_timestamp.
-- ============================================================
CREATE TABLE clean_order_reviews (
    review_id               VARCHAR2(50),            -- kept for traceability; NOT the PK
    order_id                VARCHAR2(50) NOT NULL,
    review_score            NUMBER(1),               -- 1 to 5
    review_comment_title    VARCHAR2(1000),
    review_comment_message  VARCHAR2(4000),
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP,
    CONSTRAINT pk_clean_order_reviews PRIMARY KEY (order_id)
);

-- ============================================================
-- 7. clean_orders (99,441 rows expected)
-- Rule 5A: 8 delivered orders with NULL delivery date are kept.
-- Delivery-time and late-flag calculations will use WHERE
-- order_delivered_customer_date IS NOT NULL.
-- ============================================================
CREATE TABLE clean_orders (
    order_id                      VARCHAR2(50) NOT NULL,
    customer_id                   VARCHAR2(50),
    order_status                  VARCHAR2(20),          -- lowercase: delivered | shipped | ...
    order_purchase_timestamp      TIMESTAMP,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,             -- NULL for 8 delivered orders (Rule 5A)
    order_estimated_delivery_date TIMESTAMP,
    CONSTRAINT pk_clean_orders PRIMARY KEY (order_id)
);

-- ============================================================
-- 8. clean_products (32,951 rows expected)
-- Column names corrected from source typos:
--   product_name_lenght       -> product_name_length
--   product_description_lenght-> product_description_length
-- Both English and Portuguese category names are stored.
-- 610 NULL categories -> 'Unknown'. 2 untranslated categories
-- keep their Portuguese name as the English value.
-- ============================================================
CREATE TABLE clean_products (
    product_id                    VARCHAR2(50)  NOT NULL,
    product_category_name         VARCHAR2(100),   -- Portuguese (lowercase); 'Unknown' if null
    product_category_name_english VARCHAR2(100),   -- English; Portuguese if no translation; 'Unknown' if null
    product_name_length           NUMBER(6),       -- renamed: typo fixed
    product_description_length    NUMBER(10),      -- renamed: typo fixed
    product_photos_qty            NUMBER(3),
    product_weight_g              NUMBER(10),
    product_length_cm             NUMBER(6),
    product_height_cm             NUMBER(6),
    product_width_cm              NUMBER(6),
    CONSTRAINT pk_clean_products PRIMARY KEY (product_id)
);

-- ============================================================
-- 9. clean_sellers (3,095 rows expected)
-- ============================================================
CREATE TABLE clean_sellers (
    seller_id              VARCHAR2(50) NOT NULL,
    seller_zip_code_prefix VARCHAR2(10),
    seller_city            VARCHAR2(100),
    seller_state           VARCHAR2(5),
    CONSTRAINT pk_clean_sellers PRIMARY KEY (seller_id)
);

