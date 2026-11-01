-- orders.ctl
-- Loads olist_orders_dataset.csv into stg_orders.
-- 8 columns, LF line endings, no BOM.
-- All timestamp columns stored as VARCHAR2 in staging; no date conversion
-- here. Real types are enforced in Stage 3 via TO_TIMESTAMP.

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\raw\olist_orders_dataset.csv' "str '\n'"
TRUNCATE
INTO TABLE stg_orders
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  order_id,
  customer_id,
  order_status,
  order_purchase_timestamp,
  order_approved_at,
  order_delivered_carrier_date,
  order_delivered_customer_date,
  order_estimated_delivery_date
)
