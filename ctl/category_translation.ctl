-- category_translation.ctl
-- Loads product_category_name_translation.csv into stg_category_translation.
-- 2 columns, CRLF line endings, UTF-8 BOM.
-- CRLF: the terminator is "\r\n" (two-char sequence).
-- BOM: the file starts with 3 bytes (EF BB BF). SKIP=1 skips the header
--   row entirely, so the BOM bytes are discarded with it — no extra action
--   needed.
-- Only 71 rows (small table, load first to test your connection and path).

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\raw\product_category_name_translation.csv' "str '\r\n'"
TRUNCATE
INTO TABLE stg_category_translation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  product_category_name,
  product_category_name_english
)
