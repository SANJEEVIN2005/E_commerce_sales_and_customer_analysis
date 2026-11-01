-- 01_create_staging.sql (Stage 1)
-- Creates empty staging tables mirroring the Olist CSV files.
-- Every column is VARCHAR2 so loading never fails on type errors.

BEGIN
  FOR t IN (SELECT table_name FROM user_tables
            WHERE  table_name LIKE 'STG\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' PURGE';
  END LOOP;
END;
/

CREATE TABLE stg_customers (
  customer_id              VARCHAR2(100 CHAR),
  customer_unique_id       VARCHAR2(100 CHAR),
  customer_zip_code_prefix VARCHAR2(50 CHAR),
  customer_city            VARCHAR2(200 CHAR),
  customer_state           VARCHAR2(50 CHAR)
);

CREATE TABLE stg_geolocation (
  geolocation_zip_code_prefix VARCHAR2(50 CHAR),
  geolocation_lat             VARCHAR2(100 CHAR),
  geolocation_lng             VARCHAR2(100 CHAR),
  geolocation_city            VARCHAR2(200 CHAR),
  geolocation_state           VARCHAR2(50 CHAR)
);

CREATE TABLE stg_order_items (
  order_id            VARCHAR2(100 CHAR),
  order_item_id       VARCHAR2(50 CHAR),
  product_id          VARCHAR2(100 CHAR),
  seller_id           VARCHAR2(100 CHAR),
  shipping_limit_date VARCHAR2(100 CHAR),
  price               VARCHAR2(100 CHAR),
  freight_value       VARCHAR2(100 CHAR)
);

CREATE TABLE stg_order_payments (
  order_id             VARCHAR2(100 CHAR),
  payment_sequential   VARCHAR2(50 CHAR),
  payment_type         VARCHAR2(100 CHAR),
  payment_installments VARCHAR2(50 CHAR),
  payment_value        VARCHAR2(100 CHAR)
);

CREATE TABLE stg_order_reviews (
  review_id               VARCHAR2(100 CHAR),
  order_id                VARCHAR2(100 CHAR),
  review_score            VARCHAR2(50 CHAR),
  review_comment_title    VARCHAR2(1000 CHAR),
  review_comment_message  VARCHAR2(4000 CHAR),
  review_creation_date    VARCHAR2(100 CHAR),
  review_answer_timestamp VARCHAR2(100 CHAR)
);

CREATE TABLE stg_orders (
  order_id                      VARCHAR2(100 CHAR),
  customer_id                   VARCHAR2(100 CHAR),
  order_status                  VARCHAR2(100 CHAR),
  order_purchase_timestamp      VARCHAR2(100 CHAR),
  order_approved_at             VARCHAR2(100 CHAR),
  order_delivered_carrier_date  VARCHAR2(100 CHAR),
  order_delivered_customer_date VARCHAR2(100 CHAR),
  order_estimated_delivery_date VARCHAR2(100 CHAR)
);

-- "lenght" is the source file's own spelling; staging keeps it.
CREATE TABLE stg_products (
  product_id                 VARCHAR2(100 CHAR),
  product_category_name      VARCHAR2(200 CHAR),
  product_name_lenght        VARCHAR2(50 CHAR),
  product_description_lenght VARCHAR2(50 CHAR),
  product_photos_qty         VARCHAR2(50 CHAR),
  product_weight_g           VARCHAR2(50 CHAR),
  product_length_cm          VARCHAR2(50 CHAR),
  product_height_cm          VARCHAR2(50 CHAR),
  product_width_cm           VARCHAR2(50 CHAR)
);

CREATE TABLE stg_sellers (
  seller_id              VARCHAR2(100 CHAR),
  seller_zip_code_prefix VARCHAR2(50 CHAR),
  seller_city            VARCHAR2(200 CHAR),
  seller_state           VARCHAR2(50 CHAR)
);

CREATE TABLE stg_category_translation (
  product_category_name         VARCHAR2(200 CHAR),
  product_category_name_english VARCHAR2(200 CHAR)
);