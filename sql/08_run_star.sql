-- ============================================================
-- sql/08_run_star.sql
-- Stage 4 Step 3: Execute star schema load and verify results.
--
-- HOW TO RUN:
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @sql\08_run_star.sql
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 150
SET PAGESIZE 60
SET TRIMSPOOL ON


BEGIN
    run_star_schema;
END;
/

-- ---- Audit log: show only the 6 star schema steps ----------

COLUMN step_name   FORMAT A28
COLUMN status      FORMAT A8
COLUMN rows_loaded FORMAT 9,999,999
COLUMN dur_sec     FORMAT 9999
COLUMN message     FORMAT A50 TRUNCATED

SELECT
    log_id,
    step_name,
    status,
    rows_loaded,
    ROUND((CAST(end_time AS DATE) - CAST(start_time AS DATE)) * 86400) AS dur_sec,
    SUBSTR(message, 1, 50) AS message
FROM etl_audit_log
WHERE step_name LIKE 'SP_LOAD%'
ORDER BY log_id;

-- ---- Row counts for all 6 star schema tables ---------------

COLUMN tbl     FORMAT A25
COLUMN row_cnt FORMAT 9,999,999

SELECT tbl, row_cnt FROM (
  SELECT 'dim_date'           AS tbl, COUNT(*) AS row_cnt FROM dim_date           UNION ALL
  SELECT 'dim_customer',             COUNT(*)             FROM dim_customer        UNION ALL
  SELECT 'dim_seller',               COUNT(*)             FROM dim_seller          UNION ALL
  SELECT 'dim_product',              COUNT(*)             FROM dim_product         UNION ALL
  SELECT 'fact_orders',              COUNT(*)             FROM fact_orders         UNION ALL
  SELECT 'fact_order_items',         COUNT(*)             FROM fact_order_items
) ORDER BY tbl;

-- ---- Verification 1: Total revenue across all orders -------

SELECT
    TO_CHAR(SUM(total_revenue), '999,999,999.99') AS total_revenue_brl,
    COUNT(*)                                       AS total_orders,
    TO_CHAR(AVG(total_revenue), '999,999.99')      AS avg_revenue_per_order
FROM fact_orders
WHERE order_status NOT IN ('canceled', 'unavailable');

-- ---- Verification 2: Orders by status ----------------------

COLUMN order_status FORMAT A20
COLUMN order_count  FORMAT 9,999,999
COLUMN pct          FORMAT 990.0

SELECT
    order_status,
    COUNT(*)                                          AS order_count,
    ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM fact_orders
GROUP BY order_status
ORDER BY COUNT(*) DESC;

-- ---- Verification 3: Top 10 categories by revenue ----------

COLUMN category             FORMAT A30
COLUMN category_revenue_brl FORMAT 999,999,999.99
COLUMN items_sold           FORMAT 9,999,999

SELECT
    dp.product_category_name_english          AS category,
    TO_CHAR(SUM(fi.price), '999,999,999.99')  AS category_revenue_brl,
    COUNT(*)                                   AS items_sold
FROM fact_order_items fi
JOIN dim_product dp ON dp.product_key = fi.product_key
JOIN fact_orders  fo ON fo.order_id   = fi.order_id
WHERE fo.order_status NOT IN ('canceled', 'unavailable')
GROUP BY dp.product_category_name_english
ORDER BY SUM(fi.price) DESC
FETCH FIRST 10 ROWS ONLY;

-- ---- Verification 4: Delivery performance ------------------

SELECT
    COUNT(*)                                              AS delivered_orders,
    ROUND(AVG(days_to_delivery), 1)                       AS avg_days_to_delivery,
    ROUND(MIN(days_to_delivery), 1)                       AS min_days,
    ROUND(MAX(days_to_delivery), 1)                       AS max_days,
    SUM(is_late)                                          AS late_orders,
    ROUND(SUM(is_late) * 100 / COUNT(is_late), 1)         AS pct_late
FROM fact_orders
WHERE order_status = 'delivered'
  AND days_to_delivery IS NOT NULL;

-- ---- Verification 5: Review score distribution -------------

COLUMN score   FORMAT 9
COLUMN reviews FORMAT 9,999,999

SELECT
    review_score                                           AS score,
    COUNT(*)                                               AS reviews,
    ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)      AS pct
FROM fact_orders
WHERE review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;

-- ---- Verification 6: dim_date sanity check -----------------

SELECT
    MIN(full_date)  AS first_date,
    MAX(full_date)  AS last_date,
    COUNT(*)        AS total_days,
    SUM(is_weekend) AS weekend_days
FROM dim_date;

