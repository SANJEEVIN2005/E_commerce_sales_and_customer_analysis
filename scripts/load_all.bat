@echo off
REM ============================================================
REM load_all.bat
REM Runs SQL*Loader for all 9 staging tables in the recommended order.
REM
REM HOW TO RUN (from the project root, Windows Command Prompt):
REM   scripts\load_all.bat
REM
REM IMPORTANT: Run scripts\prepare_reviews.py BEFORE this script.
REM   It must print "Rows written including header: 99225" first.
REM
REM ORDER RATIONALE
REM   1. category_translation  - smallest (71 rows), tests your connection
REM   2. sellers               - small (3,095 rows)
REM   3. products              - small (32,951 rows)
REM   4. customers             - medium
REM   5. orders                - medium (same row count as customers)
REM   6. order_payments        - medium
REM   7. order_reviews         - medium (uses prepared file)
REM   8. order_items           - larger
REM   9. geolocation           - largest (~1 million rows, load last)
REM
REM PASSWORD NOTE: sqlldr will prompt for a password for each table.
REM   Alternatively, set it once as an environment variable:
REM   SET ORACLE_PWD=yourpassword
REM   and change userid=... to userid=projectuser/%%ORACLE_PWD%%@localhost:1521/XEPDB1
REM   BUT: only do that in a private terminal session that you close afterward.
REM   NEVER commit a password to any file.
REM ============================================================

ECHO.
ECHO === 1/9  category_translation (71 rows) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\category_translation.ctl ^
  log=logs\category_translation.log ^
  bad=logs\category_translation.bad ^
  discard=logs\category_translation.dsc

ECHO.
ECHO === 2/9  sellers (3,095 rows) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\sellers.ctl ^
  log=logs\sellers.log ^
  bad=logs\sellers.bad ^
  discard=logs\sellers.dsc

ECHO.
ECHO === 3/9  products (32,951 rows) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\products.ctl ^
  log=logs\products.log ^
  bad=logs\products.bad ^
  discard=logs\products.dsc

ECHO.
ECHO === 4/9  customers (99,441 rows) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\customers.ctl ^
  log=logs\customers.log ^
  bad=logs\customers.bad ^
  discard=logs\customers.dsc

ECHO.
ECHO === 5/9  orders (99,441 rows) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\orders.ctl ^
  log=logs\orders.log ^
  bad=logs\orders.bad ^
  discard=logs\orders.dsc

ECHO.
ECHO === 6/9  order_payments (103,886 rows) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\order_payments.ctl ^
  log=logs\order_payments.log ^
  bad=logs\order_payments.bad ^
  discard=logs\order_payments.dsc

ECHO.
ECHO === 7/9  order_reviews (99,224 rows - uses prepared file) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\order_reviews.ctl ^
  log=logs\order_reviews.log ^
  bad=logs\order_reviews.bad ^
  discard=logs\order_reviews.dsc

ECHO.
ECHO === 8/9  order_items (112,650 rows) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\order_items.ctl ^
  log=logs\order_items.log ^
  bad=logs\order_items.bad ^
  discard=logs\order_items.dsc

ECHO.
ECHO === 9/9  geolocation (~1,000,163 rows - this will take a few minutes) ===
sqlldr userid=projectuser@localhost:1521/XEPDB1 ^
  control=ctl\geolocation.ctl ^
  log=logs\geolocation.log ^
  bad=logs\geolocation.bad ^
  discard=logs\geolocation.dsc

ECHO.
ECHO === QUICK LOG SUMMARY ===
ECHO Lines containing "successfully loaded" and "rejected":
findstr /C:"Rows successfully loaded" /C:"Total logical records rejected" logs\*.log

ECHO.
ECHO All done. Now run the reconciliation query in SQL*Plus:
ECHO   sqlplus projectuser@localhost:1521/XEPDB1 @sql\03_reconcile_staging.sql
ECHO.
