-- geolocation.ctl
-- Loads olist_geolocation_dataset.csv into stg_geolocation.
-- ~1 million rows; load last because it is slowest.
-- LF line endings, no BOM.
-- Lat/lng stored as VARCHAR2 in staging; converted to NUMBER in Stage 3.
-- Zip prefix stored as text to preserve leading zeros.

OPTIONS (SKIP=1, ERRORS=1000)
LOAD DATA
CHARACTERSET AL32UTF8
INFILE 'data\raw\olist_geolocation_dataset.csv' "str '\n'"
TRUNCATE
INTO TABLE stg_geolocation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  geolocation_zip_code_prefix,
  geolocation_lat,
  geolocation_lng,
  geolocation_city,
  geolocation_state
)
