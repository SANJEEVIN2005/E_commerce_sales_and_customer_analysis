-- order_items.ctl
-- Loads olist_order_items_dataset.csv into stg_order_items.
-- 7 columns, LF line endings, no BOM.
-- price and freight_value are numeric in the source but stored VARCHAR2
-- in staging; converted in Stage 3 cleaning procedures.

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\raw\olist_order_items_dataset.csv' "str '\n'"
TRUNCATE
INTO TABLE stg_order_items
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  order_id,
  order_item_id,
  product_id,
  seller_id,
  shipping_limit_date,
  price,
  freight_value
)
