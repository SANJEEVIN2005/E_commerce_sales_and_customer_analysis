-- order_reviews.ctl
-- Loads data\prepared\olist_order_reviews_prepared.csv into stg_order_reviews.
-- IMPORTANT: Use the PREPARED file (in data\prepared), NOT the raw file.
--   The raw file has embedded newlines inside quoted comment fields that
--   would confuse SQL*Loader. The Python script prepare_reviews.py flattens
--   them to single spaces. Run that script first and confirm it prints:
--   "Rows written including header: 99225"
--
-- CHAR(1000) and CHAR(4000): SQL*Loader defaults to 255 chars per field.
--   These columns can be much longer. We override with explicit sizes so
--   long comments are not silently truncated. The staging column is VARCHAR2
--   so Oracle trims the excess whitespace anyway.
-- LF line endings in the prepared file (the script uses lineterminator='\n').

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\prepared\olist_order_reviews_prepared.csv' "str '\n'"
TRUNCATE
INTO TABLE stg_order_reviews
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  review_id,
  order_id,
  review_score,
  review_comment_title    CHAR(1000),
  review_comment_message  CHAR(4000),
  review_creation_date,
  review_answer_timestamp
)
