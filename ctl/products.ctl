-- products.ctl
-- Loads olist_products_dataset.csv into stg_products.
-- 9 columns, LF line endings, no BOM.
-- NOTE: "lenght" is the source file's own misspelling of "length".
--   We keep the original column name in staging to match the CSV header
--   exactly. The clean layer (Stage 3) will rename these columns.

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\raw\olist_products_dataset.csv' "str '\n'"
TRUNCATE
INTO TABLE stg_products
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  product_id,
  product_category_name,
  product_name_lenght,
  product_description_lenght,
  product_photos_qty,
  product_weight_g,
  product_length_cm,
  product_height_cm,
  product_width_cm
)
