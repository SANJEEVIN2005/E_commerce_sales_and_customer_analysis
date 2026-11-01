-- ============================================================
-- plsql/star_procedures.sql
-- Stage 4 Step 2: Load 4 dim tables + 2 fact tables.
--
-- HOW TO RUN (compile only):
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @plsql\star_procedures.sql
--
-- HELPER FUNCTION: f_date_key
--   Converts a TIMESTAMP to a YYYYMMDD integer key.
--   Returns NULL if the timestamp is NULL or outside 2016-2019
--   (so fact rows never reference a date_key not in dim_date).
-- ============================================================

-- ---- Helper function: TIMESTAMP -> date_key integer ---------
CREATE OR REPLACE FUNCTION f_date_key(p_ts IN TIMESTAMP)
RETURN NUMBER AS
    v_d DATE;
BEGIN
    IF p_ts IS NULL THEN RETURN NULL; END IF;
    v_d := TRUNC(CAST(p_ts AS DATE));
    -- dim_date only covers 2016-01-01 to 2019-12-31
    IF v_d < DATE '2016-01-01' OR v_d > DATE '2019-12-31' THEN
        RETURN NULL;
    END IF;
    RETURN TO_NUMBER(TO_CHAR(v_d, 'YYYYMMDD'));
END f_date_key;
/
SHOW ERRORS FUNCTION f_date_key


-- ============================================================
-- 1. sp_load_dim_date
-- Generates one row per calendar day: 2016-01-01 to 2019-12-31.
-- 4 years x 365.25 avg = 1,461 rows total.
-- Uses a PL/SQL loop (no CSV needed).
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_load_dim_date AS
    v_log_id  NUMBER;
    v_loaded  NUMBER := 0;
    v_date    DATE   := DATE '2016-01-01';
    v_end     DATE   := DATE '2019-12-31';
BEGIN
    p_log_start('SP_LOAD_DIM_DATE', v_log_id);

    DELETE FROM dim_date;

    WHILE v_date <= v_end LOOP
        INSERT INTO dim_date (
            date_key,
            full_date,
            year,
            quarter,
            month_num,
            month_name,
            day_of_month,
            day_of_week,
            day_name,
            is_weekend
        ) VALUES (
            TO_NUMBER(TO_CHAR(v_date, 'YYYYMMDD')),
            v_date,
            TO_NUMBER(TO_CHAR(v_date, 'YYYY')),
            TO_NUMBER(TO_CHAR(v_date, 'Q')),
            TO_NUMBER(TO_CHAR(v_date, 'MM')),
            TRIM(TO_CHAR(v_date, 'Month')),
            TO_NUMBER(TO_CHAR(v_date, 'DD')),
            TO_NUMBER(TO_CHAR(v_date, 'D')),  -- 1=Sun ... 7=Sat
            TRIM(TO_CHAR(v_date, 'Day')),
            CASE WHEN TO_NUMBER(TO_CHAR(v_date, 'D')) IN (1, 7) THEN 1 ELSE 0 END
        );
        v_date   := v_date + 1;
        v_loaded := v_loaded + 1;
    END LOOP;

    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', NULL, v_loaded, 0,
        'Calendar: 2016-01-01 to 2019-12-31');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_load_dim_date;
/
SHOW ERRORS PROCEDURE sp_load_dim_date


-- ============================================================
-- 2. sp_load_dim_customer
-- Grain: one row per customer_unique_id (the person).
-- A single person can have multiple customer_ids (one per order),
-- so we GROUP BY customer_unique_id and pick MAX city/state/zip
-- as a representative address.
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_load_dim_customer AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_LOAD_DIM_CUSTOMER', v_log_id);

    SELECT COUNT(DISTINCT customer_unique_id) INTO v_read
    FROM clean_customers
    WHERE customer_unique_id IS NOT NULL;

    DELETE FROM dim_customer;

    INSERT INTO dim_customer (
        customer_key,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    )
    SELECT
        customer_unique_id,
        MAX(customer_zip_code_prefix),
        MAX(customer_city),
        MAX(customer_state)
    FROM clean_customers
    WHERE customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id;

    v_loaded := SQL%ROWCOUNT;
    COMMIT;

    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded,
        'Dedup: customer_id->customer_unique_id. '
        || TO_CHAR(v_read) || ' unique persons.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_load_dim_customer;
/
SHOW ERRORS PROCEDURE sp_load_dim_customer


-- ============================================================
-- 3. sp_load_dim_seller
-- Direct copy from clean_sellers.
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_load_dim_seller AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_LOAD_DIM_SELLER', v_log_id);

    SELECT COUNT(*) INTO v_read FROM clean_sellers;

    DELETE FROM dim_seller;

    INSERT INTO dim_seller (
        seller_key,
        seller_zip_code_prefix,
        seller_city,
        seller_state
    )
    SELECT
        seller_id,
        seller_zip_code_prefix,
        seller_city,
        seller_state
    FROM clean_sellers
    WHERE seller_id IS NOT NULL;

    v_loaded := SQL%ROWCOUNT;
    COMMIT;

    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded, NULL);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_load_dim_seller;
/
SHOW ERRORS PROCEDURE sp_load_dim_seller


-- ============================================================
-- 4. sp_load_dim_product
-- Direct copy from clean_products (key columns only).
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_load_dim_product AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_LOAD_DIM_PRODUCT', v_log_id);

    SELECT COUNT(*) INTO v_read FROM clean_products;

    DELETE FROM dim_product;

    INSERT INTO dim_product (
        product_key,
        product_category_name,
        product_category_name_english,
        product_weight_g,
        product_photos_qty
    )
    SELECT
        product_id,
        product_category_name,
        product_category_name_english,
        product_weight_g,
        product_photos_qty
    FROM clean_products
    WHERE product_id IS NOT NULL;

    v_loaded := SQL%ROWCOUNT;
    COMMIT;

    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded, NULL);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_load_dim_product;
/
SHOW ERRORS PROCEDURE sp_load_dim_product


-- ============================================================
-- 5. sp_load_fact_orders
-- Grain: one row per order (99,441 rows expected).
--
-- JOINS EXPLAINED:
--   clean_orders          -> the order header (status, timestamps)
--   clean_customers cc    -> bridge: customer_id -> customer_unique_id
--   dim_customer dc       -> validate the unique_id exists in the dim
--   items subquery        -> aggregated items: count, revenue, freight
--   payments subquery     -> aggregated payments: total paid
--   clean_order_reviews   -> review score (LEFT JOIN: some orders have no review)
--
-- MEASURES COMPUTED:
--   days_to_delivery = (delivered_date - purchase_date) in decimal days
--                      NULL if delivery date is NULL (Rule 5A)
--   is_late          = 1 if delivered > estimated, 0 if on time,
--                      NULL if not yet delivered (status != delivered)
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_load_fact_orders AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_LOAD_FACT_ORDERS', v_log_id);

    SELECT COUNT(*) INTO v_read FROM clean_orders;

    DELETE FROM fact_orders;

    INSERT INTO fact_orders (
        order_id,
        customer_key,
        purchase_date_key,
        order_status,
        item_count,
        total_revenue,
        freight_total,
        total_payment,
        review_score,
        days_to_delivery,
        is_late
    )
    SELECT
        o.order_id,

        -- customer_key: navigate from order-level customer_id to person-level unique_id
        dc.customer_key,

        -- purchase_date_key: YYYYMMDD integer for the dim_date join
        f_date_key(o.order_purchase_timestamp),

        o.order_status,

        -- items aggregated per order
        i.item_count,
        i.total_revenue,
        i.freight_total,

        -- payments aggregated per order
        p.total_payment,

        -- review score (NULL if order has no review)
        r.review_score,

        -- days_to_delivery: decimal days from purchase to delivery
        -- NULL when delivery date is missing (Rule 5A: 8 orders)
        CASE
            WHEN o.order_delivered_customer_date IS NOT NULL
            THEN ROUND(
                     CAST(o.order_delivered_customer_date AS DATE) -
                     CAST(o.order_purchase_timestamp      AS DATE),
                 2)
            ELSE NULL
        END,

        -- is_late: 1=late, 0=on time, NULL=not yet delivered
        CASE
            WHEN o.order_delivered_customer_date IS NULL           THEN NULL
            WHEN o.order_delivered_customer_date >
                 o.order_estimated_delivery_date                   THEN 1
            ELSE 0
        END

    FROM clean_orders o

    -- Bridge: order-level customer_id -> person-level customer_unique_id
    JOIN clean_customers cc ON cc.customer_id = o.customer_id

    -- Dim lookup: confirm unique customer exists
    JOIN dim_customer dc ON dc.customer_key = cc.customer_unique_id

    -- Item aggregates (LEFT: orders with 0 items still load; counts will be NULL)
    LEFT JOIN (
        SELECT
            order_id,
            COUNT(*)          AS item_count,
            SUM(price)        AS total_revenue,
            SUM(freight_value)AS freight_total
        FROM clean_order_items
        GROUP BY order_id
    ) i ON i.order_id = o.order_id

    -- Payment aggregates
    LEFT JOIN (
        SELECT order_id, SUM(payment_value) AS total_payment
        FROM clean_order_payments
        GROUP BY order_id
    ) p ON p.order_id = o.order_id

    -- Review (one row per order after Stage 3 dedup)
    LEFT JOIN clean_order_reviews r ON r.order_id = o.order_id;

    v_loaded := SQL%ROWCOUNT;
    COMMIT;

    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded,
        'Measures: revenue, freight, payment, review_score, days_to_delivery, is_late.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_load_fact_orders;
/
SHOW ERRORS PROCEDURE sp_load_fact_orders


-- ============================================================
-- 6. sp_load_fact_order_items
-- Grain: one row per line item (112,650 rows expected).
-- Direct copy from clean_order_items; adds date_key for ship date.
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_load_fact_order_items AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_LOAD_FACT_ORDER_ITEMS', v_log_id);

    SELECT COUNT(*) INTO v_read FROM clean_order_items;

    DELETE FROM fact_order_items;

    INSERT INTO fact_order_items (
        order_id,
        order_item_id,
        product_key,
        seller_key,
        ship_date_key,
        price,
        freight_value
    )
    SELECT
        order_id,
        order_item_id,
        product_id,     -- becomes product_key in the fact table
        seller_id,      -- becomes seller_key in the fact table
        f_date_key(shipping_limit_date),
        price,
        freight_value
    FROM clean_order_items;

    v_loaded := SQL%ROWCOUNT;
    COMMIT;

    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded, NULL);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_load_fact_order_items;
/
SHOW ERRORS PROCEDURE sp_load_fact_order_items


-- ============================================================
-- Master procedure: run_star_schema
-- Runs all 6 loaders in dependency order:
--   dims first (date, customer, seller, product)
--   facts after (orders reference dim_customer; items reference
--   dim_product and dim_seller)
-- ============================================================
CREATE OR REPLACE PROCEDURE run_star_schema AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== run_star_schema started: '
        || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') || ' ===');

    sp_load_dim_date;
    DBMS_OUTPUT.PUT_LINE('  1/6 sp_load_dim_date         DONE');

    sp_load_dim_customer;
    DBMS_OUTPUT.PUT_LINE('  2/6 sp_load_dim_customer     DONE');

    sp_load_dim_seller;
    DBMS_OUTPUT.PUT_LINE('  3/6 sp_load_dim_seller       DONE');

    sp_load_dim_product;
    DBMS_OUTPUT.PUT_LINE('  4/6 sp_load_dim_product      DONE');

    sp_load_fact_orders;
    DBMS_OUTPUT.PUT_LINE('  5/6 sp_load_fact_orders      DONE');

    sp_load_fact_order_items;
    DBMS_OUTPUT.PUT_LINE('  6/6 sp_load_fact_order_items DONE');

    DBMS_OUTPUT.PUT_LINE('=== run_star_schema finished: '
        || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') || ' ===');
END run_star_schema;
/
SHOW ERRORS PROCEDURE run_star_schema

