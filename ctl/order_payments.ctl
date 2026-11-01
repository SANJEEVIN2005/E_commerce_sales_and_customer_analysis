-- order_payments.ctl
-- Loads olist_order_payments_dataset.csv into stg_order_payments.
-- 5 columns, LF line endings, no BOM.
-- payment_value stored as VARCHAR2; converted to NUMBER in Stage 3.

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\raw\olist_order_payments_dataset.csv' "str '\n'"
TRUNCATE
INTO TABLE stg_order_payments
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  order_id,
  payment_sequential,
  payment_type,
  payment_installments,
  payment_value
)
