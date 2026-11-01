-- ============================================================
-- plsql/clean_procedures.sql
-- Stage 3 Step 3: Nine cleaning procedures + master runner.
--
-- NOTE ON NAMING
--   Each procedure is named  sp_clean_<table>  (sp = stored procedure).
--   We cannot use  clean_<table>  because a TABLE of the same name
--   already exists in this schema (ORA-00955 would block creation).
--
-- HOW TO RUN (COMPILE only -- does not execute yet):
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @plsql\clean_procedures.sql
--
-- To EXECUTE after compiling:
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @sql\06_run_cleaning.sql
-- ============================================================


-- ============================================================
-- 1. sp_clean_category_translation
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_category_translation AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_CATEGORY_TRANSLATION', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_category_translation;
    DELETE FROM clean_category_translation;
    INSERT INTO clean_category_translation (
        product_category_name,
        product_category_name_english
    )
    SELECT
        LOWER(TRIM(product_category_name)),
        LOWER(TRIM(product_category_name_english))
    FROM stg_category_translation
    WHERE NULLIF(TRIM(product_category_name), '') IS NOT NULL;
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded, NULL);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_category_translation;
/
SHOW ERRORS PROCEDURE sp_clean_category_translation


-- ============================================================
-- 2. sp_clean_customers
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_customers AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_CUSTOMERS', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_customers;
    DELETE FROM clean_customers;
    INSERT INTO clean_customers (
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    )
    SELECT
        NULLIF(TRIM(customer_id),              ''),
        NULLIF(TRIM(customer_unique_id),       ''),
        NULLIF(TRIM(customer_zip_code_prefix), ''),
        UPPER(NULLIF(TRIM(customer_city),      '')),
        UPPER(NULLIF(TRIM(customer_state),     ''))
    FROM stg_customers
    WHERE NULLIF(TRIM(customer_id), '') IS NOT NULL;
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded, NULL);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_customers;
/
SHOW ERRORS PROCEDURE sp_clean_customers


-- ============================================================
-- 3. sp_clean_sellers
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_sellers AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_SELLERS', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_sellers;
    DELETE FROM clean_sellers;
    INSERT INTO clean_sellers (
        seller_id,
        seller_zip_code_prefix,
        seller_city,
        seller_state
    )
    SELECT
        NULLIF(TRIM(seller_id),              ''),
        NULLIF(TRIM(seller_zip_code_prefix), ''),
        UPPER(NULLIF(TRIM(seller_city),      '')),
        UPPER(NULLIF(TRIM(seller_state),     ''))
    FROM stg_sellers
    WHERE NULLIF(TRIM(seller_id), '') IS NOT NULL;
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded, NULL);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_sellers;
/
SHOW ERRORS PROCEDURE sp_clean_sellers


-- ============================================================
-- 4. sp_clean_products
-- Rule 4A: NULL category -> 'Unknown'.
--          2 untranslated categories -> keep Portuguese name.
-- Joins to stg_category_translation (not clean_) so we can
-- run this procedure even before clean_category_translation
-- is fully committed. LEFT JOIN keeps all products.
-- Column name typos corrected: lenght -> length.
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_products AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_PRODUCTS', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_products;
    DELETE FROM clean_products;
    INSERT INTO clean_products (
        product_id,
        product_category_name,
        product_category_name_english,
        product_name_length,
        product_description_length,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm
    )
    SELECT
        NULLIF(TRIM(p.product_id), ''),
        CASE
            WHEN NULLIF(TRIM(p.product_category_name), '') IS NULL THEN 'Unknown'
            ELSE LOWER(TRIM(p.product_category_name))
        END,
        CASE
            WHEN NULLIF(TRIM(p.product_category_name), '') IS NULL THEN 'Unknown'
            WHEN t.product_category_name_english IS NOT NULL
                THEN LOWER(TRIM(t.product_category_name_english))
            ELSE LOWER(TRIM(p.product_category_name))
        END,
        TO_NUMBER(NULLIF(TRIM(p.product_name_lenght),        '')),
        TO_NUMBER(NULLIF(TRIM(p.product_description_lenght), '')),
        TO_NUMBER(NULLIF(TRIM(p.product_photos_qty),         '')),
        TO_NUMBER(NULLIF(TRIM(p.product_weight_g),           '')),
        TO_NUMBER(NULLIF(TRIM(p.product_length_cm),          '')),
        TO_NUMBER(NULLIF(TRIM(p.product_height_cm),          '')),
        TO_NUMBER(NULLIF(TRIM(p.product_width_cm),           ''))
    FROM stg_products p
    LEFT JOIN stg_category_translation t
           ON LOWER(TRIM(p.product_category_name)) = LOWER(TRIM(t.product_category_name))
    WHERE NULLIF(TRIM(p.product_id), '') IS NOT NULL;
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded,
        'Rule 4A: NULL cat->Unknown. 2 untranslated kept in Portuguese.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_products;
/
SHOW ERRORS PROCEDURE sp_clean_products


-- ============================================================
-- 5. sp_clean_orders
-- Rule 5A: 8 delivered orders with NULL delivery date are kept.
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_orders AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_ORDERS', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_orders;
    DELETE FROM clean_orders;
    INSERT INTO clean_orders (
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date
    )
    SELECT
        NULLIF(TRIM(order_id),    ''),
        NULLIF(TRIM(customer_id), ''),
        LOWER(NULLIF(TRIM(order_status), '')),
        TO_TIMESTAMP(NULLIF(TRIM(order_purchase_timestamp),      ''), 'YYYY-MM-DD HH24:MI:SS'),
        TO_TIMESTAMP(NULLIF(TRIM(order_approved_at),             ''), 'YYYY-MM-DD HH24:MI:SS'),
        TO_TIMESTAMP(NULLIF(TRIM(order_delivered_carrier_date),  ''), 'YYYY-MM-DD HH24:MI:SS'),
        TO_TIMESTAMP(NULLIF(TRIM(order_delivered_customer_date), ''), 'YYYY-MM-DD HH24:MI:SS'),
        TO_TIMESTAMP(NULLIF(TRIM(order_estimated_delivery_date), ''), 'YYYY-MM-DD HH24:MI:SS')
    FROM stg_orders
    WHERE NULLIF(TRIM(order_id), '') IS NOT NULL;
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded,
        'Rule 5A: 8 delivered orders with NULL delivery date kept.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_orders;
/
SHOW ERRORS PROCEDURE sp_clean_orders


-- ============================================================
-- 6. sp_clean_order_items
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_order_items AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_ORDER_ITEMS', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_order_items;
    DELETE FROM clean_order_items;
    INSERT INTO clean_order_items (
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
    )
    SELECT
        NULLIF(TRIM(order_id),   ''),
        TO_NUMBER(NULLIF(TRIM(order_item_id), '')),
        NULLIF(TRIM(product_id), ''),
        NULLIF(TRIM(seller_id),  ''),
        TO_TIMESTAMP(NULLIF(TRIM(shipping_limit_date), ''), 'YYYY-MM-DD HH24:MI:SS'),
        TO_NUMBER(NULLIF(TRIM(price),         '')),
        TO_NUMBER(NULLIF(TRIM(freight_value), ''))
    FROM stg_order_items
    WHERE NULLIF(TRIM(order_id),      '') IS NOT NULL
      AND NULLIF(TRIM(order_item_id), '') IS NOT NULL;
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded, NULL);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_order_items;
/
SHOW ERRORS PROCEDURE sp_clean_order_items


-- ============================================================
-- 7. sp_clean_order_payments
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_order_payments AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_ORDER_PAYMENTS', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_order_payments;
    DELETE FROM clean_order_payments;
    INSERT INTO clean_order_payments (
        order_id,
        payment_sequential,
        payment_type,
        payment_installments,
        payment_value
    )
    SELECT
        NULLIF(TRIM(order_id),              ''),
        TO_NUMBER(NULLIF(TRIM(payment_sequential),   '')),
        LOWER(NULLIF(TRIM(payment_type),             '')),
        TO_NUMBER(NULLIF(TRIM(payment_installments), '')),
        TO_NUMBER(NULLIF(TRIM(payment_value),        ''))
    FROM stg_order_payments
    WHERE NULLIF(TRIM(order_id),           '') IS NOT NULL
      AND NULLIF(TRIM(payment_sequential), '') IS NOT NULL;
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded, NULL);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_order_payments;
/
SHOW ERRORS PROCEDURE sp_clean_order_payments


-- ============================================================
-- 8. sp_clean_order_reviews
-- Rule 1A: keep latest review_answer_timestamp per order_id.
-- Ties broken by latest review_creation_date. NULLS LAST.
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_order_reviews AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_ORDER_REVIEWS', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_order_reviews;
    DELETE FROM clean_order_reviews;
    INSERT INTO clean_order_reviews (
        review_id,
        order_id,
        review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date,
        review_answer_timestamp
    )
    SELECT
        NULLIF(TRIM(review_id),              ''),
        NULLIF(TRIM(order_id),               ''),
        TO_NUMBER(NULLIF(TRIM(review_score), '')),
        NULLIF(TRIM(review_comment_title),   ''),
        NULLIF(TRIM(review_comment_message), ''),
        TO_TIMESTAMP(NULLIF(TRIM(review_creation_date),    ''), 'YYYY-MM-DD HH24:MI:SS'),
        TO_TIMESTAMP(NULLIF(TRIM(review_answer_timestamp), ''), 'YYYY-MM-DD HH24:MI:SS')
    FROM (
        SELECT
            review_id,
            order_id,
            review_score,
            review_comment_title,
            review_comment_message,
            review_creation_date,
            review_answer_timestamp,
            ROW_NUMBER() OVER (
                PARTITION BY TRIM(order_id)
                ORDER BY
                    TO_TIMESTAMP(NULLIF(TRIM(review_answer_timestamp),''),'YYYY-MM-DD HH24:MI:SS') DESC NULLS LAST,
                    TO_TIMESTAMP(NULLIF(TRIM(review_creation_date),   ''),'YYYY-MM-DD HH24:MI:SS') DESC NULLS LAST
            ) AS rn
        FROM stg_order_reviews
        WHERE NULLIF(TRIM(order_id), '') IS NOT NULL
    )
    WHERE rn = 1;
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded,
        'Rule 1A: dedup to 1 review per order_id (latest answer timestamp).');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_order_reviews;
/
SHOW ERRORS PROCEDURE sp_clean_order_reviews


-- ============================================================
-- 9. sp_clean_geolocation
-- Rule 2A: 1 row per zip prefix. AVG lat/lng, MIN city/state.
-- REGEXP_LIKE guard prevents ORA-01722 on non-numeric values.
-- ~1 million rows -> may take 1-3 minutes. This is normal.
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clean_geolocation AS
    v_log_id  NUMBER;
    v_read    NUMBER;
    v_loaded  NUMBER;
BEGIN
    p_log_start('SP_CLEAN_GEOLOCATION', v_log_id);
    SELECT COUNT(*) INTO v_read FROM stg_geolocation;
    DELETE FROM clean_geolocation;
    INSERT INTO clean_geolocation (
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state
    )
    SELECT
        TRIM(geolocation_zip_code_prefix),
        ROUND(AVG(TO_NUMBER(TRIM(geolocation_lat))), 6),
        ROUND(AVG(TO_NUMBER(TRIM(geolocation_lng))), 6),
        UPPER(MIN(TRIM(geolocation_city))),
        UPPER(MIN(TRIM(geolocation_state)))
    FROM stg_geolocation
    WHERE NULLIF(TRIM(geolocation_zip_code_prefix), '') IS NOT NULL
      AND REGEXP_LIKE(TRIM(geolocation_lat), '^-?[[:digit:]]+\.?[[:digit:]]*$')
      AND REGEXP_LIKE(TRIM(geolocation_lng), '^-?[[:digit:]]+\.?[[:digit:]]*$')
    GROUP BY TRIM(geolocation_zip_code_prefix);
    v_loaded := SQL%ROWCOUNT;
    COMMIT;
    p_log_end(v_log_id, 'SUCCESS', v_read, v_loaded, v_read - v_loaded,
        'Rule 2A: ' || TO_CHAR(v_read) || ' rows -> ' || TO_CHAR(v_loaded) || ' zip prefixes.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_log_end(v_log_id, 'ERROR', NULL, NULL, NULL, SQLERRM);
        RAISE;
END sp_clean_geolocation;
/
SHOW ERRORS PROCEDURE sp_clean_geolocation


-- ============================================================
-- Master procedure: run_all_cleaning
-- Calls all 9 sp_clean_* procedures in dependency order.
-- ============================================================
CREATE OR REPLACE PROCEDURE run_all_cleaning AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== run_all_cleaning started: '
        || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') || ' ===');

    sp_clean_category_translation;
    DBMS_OUTPUT.PUT_LINE('  1/9 sp_clean_category_translation  DONE');

    sp_clean_customers;
    DBMS_OUTPUT.PUT_LINE('  2/9 sp_clean_customers             DONE');

    sp_clean_sellers;
    DBMS_OUTPUT.PUT_LINE('  3/9 sp_clean_sellers               DONE');

    sp_clean_products;
    DBMS_OUTPUT.PUT_LINE('  4/9 sp_clean_products              DONE');

    sp_clean_orders;
    DBMS_OUTPUT.PUT_LINE('  5/9 sp_clean_orders                DONE');

    sp_clean_order_items;
    DBMS_OUTPUT.PUT_LINE('  6/9 sp_clean_order_items           DONE');

    sp_clean_order_payments;
    DBMS_OUTPUT.PUT_LINE('  7/9 sp_clean_order_payments        DONE');

    sp_clean_order_reviews;
    DBMS_OUTPUT.PUT_LINE('  8/9 sp_clean_order_reviews         DONE');

    sp_clean_geolocation;
    DBMS_OUTPUT.PUT_LINE('  9/9 sp_clean_geolocation           DONE');

    DBMS_OUTPUT.PUT_LINE('=== run_all_cleaning finished: '
        || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') || ' ===');
END run_all_cleaning;
/
SHOW ERRORS PROCEDURE run_all_cleaning

