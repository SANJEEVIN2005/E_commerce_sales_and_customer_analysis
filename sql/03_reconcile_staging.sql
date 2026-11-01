-- 03_reconcile_staging.sql
-- ============================================================
-- PURPOSE
--   After all 9 SQL*Loader jobs finish, run this script in SQL*Plus
--   to confirm every staging table has exactly the right number of rows.
--
-- HOW TO RUN (from the project root, Windows Command Prompt):
--   sqlplus projectuser@localhost:1521/XEPDB1 @sql\03_reconcile_staging.sql
--   (type your password when prompted)
--
-- WHAT TO LOOK FOR
--   All 9 rows in the STATUS column should say OK.
--   If any say CHECK .bad FILE, open the corresponding .bad file in the
--   logs\ folder. The log file will show the rejection reason.
-- ============================================================

SET LINESIZE 100
SET PAGESIZE 50
COLUMN tbl             FORMAT A30
COLUMN csv_rows        FORMAT 999,999,999
COLUMN loaded          FORMAT 999,999,999
COLUMN rejected_or_missing FORMAT 999,999,999
COLUMN status          FORMAT A16


WITH expected AS (
  -- These numbers come from the actual CSV record counts in section 4
  -- of the project brief. They EXCLUDE the header row.
  SELECT 'STG_CUSTOMERS'           AS tbl, 99441   AS csv_rows FROM dual UNION ALL
  SELECT 'STG_GEOLOCATION',                1000163             FROM dual UNION ALL
  SELECT 'STG_ORDER_ITEMS',               112650              FROM dual UNION ALL
  SELECT 'STG_ORDER_PAYMENTS',            103886              FROM dual UNION ALL
  SELECT 'STG_ORDER_REVIEWS',             99224               FROM dual UNION ALL
  SELECT 'STG_ORDERS',                    99441               FROM dual UNION ALL
  SELECT 'STG_PRODUCTS',                  32951               FROM dual UNION ALL
  SELECT 'STG_SELLERS',                   3095                FROM dual UNION ALL
  SELECT 'STG_CATEGORY_TRANSLATION',      71                  FROM dual
),
loaded AS (
  -- COUNT(*) hits each staging table in the database
  SELECT 'STG_CUSTOMERS'          AS tbl, COUNT(*) AS n FROM stg_customers          UNION ALL
  SELECT 'STG_GEOLOCATION',               COUNT(*)      FROM stg_geolocation         UNION ALL
  SELECT 'STG_ORDER_ITEMS',               COUNT(*)      FROM stg_order_items         UNION ALL
  SELECT 'STG_ORDER_PAYMENTS',            COUNT(*)      FROM stg_order_payments      UNION ALL
  SELECT 'STG_ORDER_REVIEWS',             COUNT(*)      FROM stg_order_reviews       UNION ALL
  SELECT 'STG_ORDERS',                    COUNT(*)      FROM stg_orders              UNION ALL
  SELECT 'STG_PRODUCTS',                  COUNT(*)      FROM stg_products            UNION ALL
  SELECT 'STG_SELLERS',                   COUNT(*)      FROM stg_sellers             UNION ALL
  SELECT 'STG_CATEGORY_TRANSLATION',      COUNT(*)      FROM stg_category_translation
)
SELECT
  e.tbl,
  e.csv_rows,
  l.n                             AS loaded,
  e.csv_rows - l.n               AS rejected_or_missing,
  CASE WHEN e.csv_rows = l.n
       THEN 'OK'
       ELSE 'CHECK .bad FILE'
  END                             AS status
FROM expected e
JOIN loaded   l ON l.tbl = e.tbl
ORDER BY e.tbl;


-- Expected: AL32UTF8 for both VALUE columns.
-- If you see WE8MSWIN1252 or similar, the accented city names (e.g. sao paulo)
-- may have loaded incorrectly. Stop and report this before proceeding.
SELECT parameter, value
FROM   nls_database_parameters
WHERE  parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET')
ORDER BY parameter;


SELECT DISTINCT geolocation_city
FROM   stg_geolocation
WHERE  geolocation_city LIKE 's_o paulo';
