-- customers.ctl
-- Loads olist_customers_dataset.csv into stg_customers.
-- 5 columns, LF line endings, no BOM.
-- Zip code prefix kept as text (VARCHAR2) because leading zeros matter.

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\raw\olist_customers_dataset.csv' "str '\n'"
TRUNCATE
INTO TABLE stg_customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  customer_id,
  customer_unique_id,
  customer_zip_code_prefix,
  customer_city,
  customer_state
)
