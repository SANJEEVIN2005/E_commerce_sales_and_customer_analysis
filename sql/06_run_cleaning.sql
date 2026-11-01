-- ============================================================
-- sql/06_run_cleaning.sql
-- Stage 3 Step 4: Execute all cleaning procedures and verify results.
--
-- HOW TO RUN:
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @sql\06_run_cleaning.sql
--
-- WHAT TO EXPECT
--   * DBMS_OUTPUT lines confirming each of the 9 procedures.
--   * Audit log: 9 rows, all STATUS = SUCCESS.
--   * Row counts: clean_* tables should match or be less than stg_* tables
--     (fewer for geolocation due to dedup, fewer for reviews due to dedup).
--   * Sample check: see the top 10 product categories with English names.
--
-- GEOLOCATION NOTE
--   clean_geolocation processes 1 million rows. It may take 1-3 minutes.
--   You will see no output during that time -- this is normal.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 140
SET PAGESIZE 80
SET TRIMSPOOL ON


-- Execute all 9 cleaning procedures via the master runner.
-- NOTE: sp_clean_geolocation processes 1 million rows; expect ~1-3 min of silence.
BEGIN
    run_all_cleaning;
END;
/


COLUMN step_name     FORMAT A30
COLUMN status        FORMAT A10
COLUMN rows_read     FORMAT 9,999,999
COLUMN rows_loaded   FORMAT 9,999,999
COLUMN rows_rejected FORMAT 9,999,999
COLUMN dur_sec       FORMAT 99999
COLUMN message       FORMAT A55 TRUNCATED

SELECT
    log_id,
    step_name,
    status,
    rows_read,
    rows_loaded,
    rows_rejected,
    ROUND(
        (CAST(end_time AS DATE) - CAST(start_time AS DATE)) * 86400
    ) AS dur_sec,
    SUBSTR(message, 1, 55) AS message
FROM etl_audit_log
ORDER BY log_id;


COLUMN tbl  FORMAT A35
COLUMN rows FORMAT 9,999,999

SELECT tbl, rows FROM (
  SELECT 'CLEAN_CATEGORY_TRANSLATION' AS tbl, COUNT(*) AS rows FROM clean_category_translation UNION ALL
  SELECT 'CLEAN_CUSTOMERS',                    COUNT(*)         FROM clean_customers            UNION ALL
  SELECT 'CLEAN_GEOLOCATION',                  COUNT(*)         FROM clean_geolocation          UNION ALL
  SELECT 'CLEAN_ORDER_ITEMS',                  COUNT(*)         FROM clean_order_items          UNION ALL
  SELECT 'CLEAN_ORDER_PAYMENTS',               COUNT(*)         FROM clean_order_payments       UNION ALL
  SELECT 'CLEAN_ORDER_REVIEWS',                COUNT(*)         FROM clean_order_reviews        UNION ALL
  SELECT 'CLEAN_ORDERS',                       COUNT(*)         FROM clean_orders               UNION ALL
  SELECT 'CLEAN_PRODUCTS',                     COUNT(*)         FROM clean_products             UNION ALL
  SELECT 'CLEAN_SELLERS',                      COUNT(*)         FROM clean_sellers
) ORDER BY tbl;


COLUMN product_category_name         FORMAT A35
COLUMN product_category_name_english FORMAT A35
COLUMN product_count                 FORMAT 9,999

SELECT product_category_name,
       product_category_name_english,
       COUNT(*) AS product_count
FROM   clean_products
GROUP  BY product_category_name, product_category_name_english
ORDER  BY COUNT(*) DESC
FETCH FIRST 10 ROWS ONLY;


SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (
    SELECT order_id, COUNT(*) AS n
    FROM   clean_order_reviews
    GROUP  BY order_id
    HAVING COUNT(*) > 1
);


SELECT COUNT(*)                     AS total_rows,
       COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zips,
       CASE WHEN COUNT(*) = COUNT(DISTINCT geolocation_zip_code_prefix)
            THEN 'OK - one row per zip prefix'
            ELSE 'CHECK - duplicates remain'
       END AS dedup_status
FROM clean_geolocation;


SELECT COUNT(*) AS delivered_with_null_date
FROM   clean_orders
WHERE  order_status = 'delivered'
  AND  order_delivered_customer_date IS NULL;


SELECT product_category_name,
       product_category_name_english,
       COUNT(*) AS products
FROM   clean_products
WHERE  product_category_name = 'Unknown'
   OR  product_category_name = product_category_name_english  -- untranslated: same in both columns
GROUP  BY product_category_name, product_category_name_english
ORDER  BY COUNT(*) DESC;

