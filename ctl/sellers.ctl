-- sellers.ctl
-- Loads olist_sellers_dataset.csv into stg_sellers.
-- 4 columns, LF line endings, no BOM.
-- Zip prefix stored as text (VARCHAR2) to preserve leading zeros.

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\raw\olist_sellers_dataset.csv' "str '\n'"
TRUNCATE
INTO TABLE stg_sellers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  seller_id,
  seller_zip_code_prefix,
  seller_city,
  seller_state
)
