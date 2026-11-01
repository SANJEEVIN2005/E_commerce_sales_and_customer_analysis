-- ============================================================
-- sql/09_analysis_queries.sql
-- Stage 5: Portfolio Analysis Queries
--
-- 10 business questions answered using the star schema.
-- All queries are SELECT only (read-only, safe to re-run).
--
-- HOW TO RUN:
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @sql\09_analysis_queries.sql
--
-- QUERIES IN THIS FILE
--   Q1.  Monthly Revenue Trend          (window fn: LAG for MoM growth)
--   Q2.  RFM Customer Segmentation      (CTE + NTILE quintiles)
--   Q3.  Category Performance Dashboard (revenue + review + delivery)
--   Q4.  Seller Leaderboard             (top 10 sellers)
--   Q5.  State Performance              (orders, revenue, delivery by state)
--   Q6.  Payment Method Analysis        (type, installments, value)
--   Q7.  Review Score by Category       (best/worst rated categories)
--   Q8.  Peak Shopping Day of Week      (when do customers buy?)
--   Q9.  Delivery Time Distribution     (speed buckets)
--   Q10. Repeat vs First-Time Customers (loyalty insight)
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
SET TRIMSPOOL ON

-- ============================================================
-- Q1. Monthly Revenue Trend
-- Shows revenue per month with month-over-month growth %.
-- Uses LAG() window function to compare each month to the
-- previous month without a self-join.
-- Revenue definition: price only, excludes cancelled/unavailable.
-- ============================================================

COLUMN yr          FORMAT 9999
COLUMN mth         FORMAT 99
COLUMN month_name  FORMAT A10
COLUMN orders      FORMAT 9,999,999
COLUMN revenue     FORMAT 999,999,999.99
COLUMN mom_pct     FORMAT 999.0

SELECT
    d.year                                              AS yr,
    d.month_num                                         AS mth,
    d.month_name,
    COUNT(fo.order_id)                                  AS orders,
    ROUND(SUM(fo.total_revenue), 2)                     AS revenue,
    ROUND(
        (SUM(fo.total_revenue)
         - LAG(SUM(fo.total_revenue)) OVER (ORDER BY d.year, d.month_num))
        * 100
        / NULLIF(LAG(SUM(fo.total_revenue)) OVER (ORDER BY d.year, d.month_num), 0)
    , 1)                                                AS mom_pct
FROM fact_orders fo
JOIN dim_date d ON d.date_key = fo.purchase_date_key
WHERE fo.order_status NOT IN ('canceled', 'unavailable')
GROUP BY d.year, d.month_num, d.month_name
ORDER BY d.year, d.month_num;


-- ============================================================
-- Q2. RFM Customer Segmentation
-- Recency   = days since last order (lower = better)
-- Frequency = number of orders placed
-- Monetary  = total revenue spent
-- Each dimension is split into 5 equal buckets (NTILE(5)).
-- Score 5 = best; score 1 = worst.
-- For Recency: we invert (more recent = higher score).
-- ============================================================

COLUMN segment        FORMAT A25
COLUMN customers      FORMAT 9,999,999
COLUMN pct_customers  FORMAT 990.0
COLUMN avg_recency    FORMAT 9,999
COLUMN avg_orders     FORMAT 990.0
COLUMN avg_monetary   FORMAT 999,999.99

WITH
-- Reference date = the latest purchase date in the dataset
ref AS (
    SELECT MAX(d.full_date) AS ref_date
    FROM fact_orders fo
    JOIN dim_date d ON d.date_key = fo.purchase_date_key
    WHERE fo.purchase_date_key IS NOT NULL
),
-- One row per customer: last order date, order count, total spend
rfm_raw AS (
    SELECT
        fo.customer_key,
        MAX(d.full_date)     AS last_order_date,
        COUNT(fo.order_id)   AS frequency,
        SUM(fo.total_revenue)AS monetary
    FROM fact_orders fo
    JOIN dim_date d ON d.date_key = fo.purchase_date_key
    WHERE fo.order_status NOT IN ('canceled', 'unavailable')
      AND fo.purchase_date_key IS NOT NULL
    GROUP BY fo.customer_key
),
-- Assign 1-5 scores using NTILE(5) on each dimension
rfm_scored AS (
    SELECT
        customer_key,
        TRUNC(CAST((SELECT ref_date FROM ref) AS DATE)
              - CAST(last_order_date AS DATE))    AS recency_days,
        frequency,
        ROUND(monetary, 2)                        AS monetary,
        -- Recency: recent customers get score 5 (we order ASC so most-recent = highest tile)
        6 - NTILE(5) OVER (ORDER BY last_order_date ASC)  AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)            AS f_score,
        NTILE(5) OVER (ORDER BY monetary   ASC)           AS m_score
    FROM rfm_raw
),
-- Label each customer into a named segment
rfm_labeled AS (
    SELECT
        customer_key,
        recency_days,
        frequency,
        monetary,
        r_score,
        f_score,
        m_score,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
                THEN 'Champions'
            WHEN r_score >= 4 AND f_score >= 3
                THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2
                THEN 'Potential Loyalists'
            WHEN r_score = 3  AND f_score >= 3
                THEN 'At Risk'
            WHEN r_score <= 2 AND f_score >= 3
                THEN 'Cannot Lose Them'
            WHEN r_score <= 2 AND f_score <= 2
                THEN 'Lost'
            ELSE 'Needs Attention'
        END AS segment
    FROM rfm_scored
)
SELECT
    segment,
    COUNT(*)                                               AS customers,
    ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)      AS pct_customers,
    ROUND(AVG(recency_days))                               AS avg_recency,
    ROUND(AVG(frequency), 1)                               AS avg_orders,
    ROUND(AVG(monetary), 2)                                AS avg_monetary
FROM rfm_labeled
GROUP BY segment
ORDER BY COUNT(*) DESC;


-- ============================================================
-- Q3. Category Performance Dashboard
-- Top 15 categories ranked by revenue.
-- Shows: revenue, items sold, avg review score, avg delivery days,
--        and the % of orders that were delivered late.
-- ============================================================

COLUMN category        FORMAT A30
COLUMN orders          FORMAT 9,999,999
COLUMN items_sold      FORMAT 9,999,999
COLUMN revenue         FORMAT 999,999,999.99
COLUMN avg_review      FORMAT 9.99
COLUMN avg_del_days    FORMAT 999.9
COLUMN late_pct        FORMAT 990.0

SELECT
    dp.product_category_name_english               AS category,
    COUNT(DISTINCT fo.order_id)                    AS orders,
    COUNT(fi.order_item_id)                        AS items_sold,
    ROUND(SUM(fi.price), 2)                        AS revenue,
    ROUND(AVG(fo.review_score), 2)                 AS avg_review,
    ROUND(AVG(fo.days_to_delivery), 1)             AS avg_del_days,
    ROUND(
        SUM(CASE WHEN fo.is_late = 1 THEN 1 ELSE 0 END)
        * 100
        / NULLIF(COUNT(CASE WHEN fo.is_late IS NOT NULL THEN 1 END), 0)
    , 1)                                           AS late_pct
FROM fact_order_items fi
JOIN dim_product dp ON dp.product_key   = fi.product_key
JOIN fact_orders  fo ON fo.order_id     = fi.order_id
WHERE fo.order_status NOT IN ('canceled', 'unavailable')
GROUP BY dp.product_category_name_english
ORDER BY SUM(fi.price) DESC
FETCH FIRST 15 ROWS ONLY;


-- ============================================================
-- Q4. Seller Leaderboard (Top 10 by Revenue)
-- Shows each seller's city, state, revenue, order count,
-- avg review score, avg delivery time, and product variety.
-- ============================================================

COLUMN seller_id       FORMAT A36
COLUMN city            FORMAT A20
COLUMN st              FORMAT A3
COLUMN orders          FORMAT 9,999
COLUMN revenue         FORMAT 999,999,999.99
COLUMN avg_review      FORMAT 9.99
COLUMN avg_del_days    FORMAT 999.9
COLUMN products        FORMAT 9,999

SELECT
    ds.seller_key                              AS seller_id,
    ds.seller_city                             AS city,
    ds.seller_state                            AS st,
    COUNT(DISTINCT fi.order_id)                AS orders,
    ROUND(SUM(fi.price), 2)                    AS revenue,
    ROUND(AVG(fo.review_score), 2)             AS avg_review,
    ROUND(AVG(fo.days_to_delivery), 1)         AS avg_del_days,
    COUNT(DISTINCT fi.product_key)             AS products
FROM fact_order_items fi
JOIN dim_seller  ds ON ds.seller_key = fi.seller_key
JOIN fact_orders fo ON fo.order_id   = fi.order_id
WHERE fo.order_status NOT IN ('canceled', 'unavailable')
GROUP BY ds.seller_key, ds.seller_city, ds.seller_state
ORDER BY SUM(fi.price) DESC
FETCH FIRST 10 ROWS ONLY;


-- ============================================================
-- Q5. State Performance
-- Customer state-level summary: orders, revenue, avg delivery,
-- late %, avg review. Ordered by order volume descending.
-- ============================================================

COLUMN state           FORMAT A6
COLUMN orders          FORMAT 9,999,999
COLUMN revenue         FORMAT 999,999,999.99
COLUMN avg_del_days    FORMAT 999.9
COLUMN late_pct        FORMAT 990.0
COLUMN avg_review      FORMAT 9.99

SELECT
    dc.customer_state                                          AS state,
    COUNT(fo.order_id)                                        AS orders,
    ROUND(SUM(fo.total_revenue), 2)                           AS revenue,
    ROUND(AVG(fo.days_to_delivery), 1)                        AS avg_del_days,
    ROUND(SUM(fo.is_late) * 100
          / NULLIF(COUNT(CASE WHEN fo.is_late IS NOT NULL THEN 1 END), 0), 1) AS late_pct,
    ROUND(AVG(fo.review_score), 2)                            AS avg_review
FROM fact_orders fo
JOIN dim_customer dc ON dc.customer_key = fo.customer_key
WHERE fo.order_status NOT IN ('canceled', 'unavailable')
GROUP BY dc.customer_state
ORDER BY COUNT(fo.order_id) DESC;


-- ============================================================
-- Q6. Payment Method Analysis
-- Which payment types do customers use?
-- avg_installments shows credit card usage pattern.
-- Note: We query clean_order_payments directly because
--       payment detail is not in the star schema fact tables
--       (each order can have multiple payment rows / types).
-- ============================================================

COLUMN payment_type        FORMAT A15
COLUMN payment_rows        FORMAT 9,999,999
COLUMN pct_rows            FORMAT 990.0
COLUMN total_paid          FORMAT 999,999,999.99
COLUMN avg_installments    FORMAT 99.9
COLUMN avg_payment_value   FORMAT 99,999.99

SELECT
    payment_type,
    COUNT(*)                                              AS payment_rows,
    ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)     AS pct_rows,
    ROUND(SUM(payment_value), 2)                          AS total_paid,
    ROUND(AVG(payment_installments), 1)                   AS avg_installments,
    ROUND(AVG(payment_value), 2)                          AS avg_payment_value
FROM clean_order_payments
WHERE payment_type IS NOT NULL
GROUP BY payment_type
ORDER BY COUNT(*) DESC;


-- ============================================================
-- Q7. Review Score by Category (Best and Worst Rated)
-- Only includes categories with >= 100 reviews (statistically
-- meaningful). Shows top 10 and bottom 10 by avg score.
-- ============================================================

COLUMN category      FORMAT A30
COLUMN reviews       FORMAT 9,999,999
COLUMN avg_score     FORMAT 9.99
COLUMN pct_5star     FORMAT 990.0
COLUMN pct_1star     FORMAT 990.0

SELECT
    dp.product_category_name_english                   AS category,
    COUNT(fo.review_score)                             AS reviews,
    ROUND(AVG(fo.review_score), 2)                     AS avg_score,
    ROUND(SUM(CASE WHEN fo.review_score = 5 THEN 1 ELSE 0 END)
          * 100 / NULLIF(COUNT(fo.review_score), 0), 1) AS pct_5star,
    ROUND(SUM(CASE WHEN fo.review_score = 1 THEN 1 ELSE 0 END)
          * 100 / NULLIF(COUNT(fo.review_score), 0), 1) AS pct_1star
FROM fact_order_items fi
JOIN dim_product dp ON dp.product_key = fi.product_key
JOIN fact_orders  fo ON fo.order_id   = fi.order_id
WHERE fo.review_score IS NOT NULL
  AND fo.order_status NOT IN ('canceled', 'unavailable')
GROUP BY dp.product_category_name_english
HAVING COUNT(fo.review_score) >= 100
ORDER BY AVG(fo.review_score) DESC
FETCH FIRST 10 ROWS ONLY;


SELECT
    dp.product_category_name_english                    AS category,
    COUNT(fo.review_score)                              AS reviews,
    ROUND(AVG(fo.review_score), 2)                      AS avg_score,
    ROUND(SUM(CASE WHEN fo.review_score = 5 THEN 1 ELSE 0 END)
          * 100 / NULLIF(COUNT(fo.review_score), 0), 1) AS pct_5star,
    ROUND(SUM(CASE WHEN fo.review_score = 1 THEN 1 ELSE 0 END)
          * 100 / NULLIF(COUNT(fo.review_score), 0), 1) AS pct_1star
FROM fact_order_items fi
JOIN dim_product dp ON dp.product_key = fi.product_key
JOIN fact_orders  fo ON fo.order_id   = fi.order_id
WHERE fo.review_score IS NOT NULL
  AND fo.order_status NOT IN ('canceled', 'unavailable')
GROUP BY dp.product_category_name_english
HAVING COUNT(fo.review_score) >= 100
ORDER BY AVG(fo.review_score) ASC
FETCH FIRST 10 ROWS ONLY;


-- ============================================================
-- Q8. Peak Shopping Day of Week
-- Which day do customers place the most orders?
-- day_of_week: 1=Sunday, 2=Monday ... 7=Saturday (Oracle default).
-- ============================================================

COLUMN day_name        FORMAT A12
COLUMN orders          FORMAT 9,999,999
COLUMN pct_orders      FORMAT 990.0
COLUMN revenue         FORMAT 999,999,999.99
COLUMN avg_order_value FORMAT 99,999.99

SELECT
    d.day_of_week,
    d.day_name,
    COUNT(fo.order_id)                                      AS orders,
    ROUND(COUNT(fo.order_id) * 100 / SUM(COUNT(fo.order_id)) OVER (), 1) AS pct_orders,
    ROUND(SUM(fo.total_revenue), 2)                         AS revenue,
    ROUND(AVG(fo.total_revenue), 2)                         AS avg_order_value
FROM fact_orders fo
JOIN dim_date d ON d.date_key = fo.purchase_date_key
WHERE fo.order_status NOT IN ('canceled', 'unavailable')
GROUP BY d.day_of_week, d.day_name
ORDER BY d.day_of_week;


-- ============================================================
-- Q9. Delivery Time Distribution
-- Groups delivered orders into speed buckets.
-- Helps identify what fraction of customers get fast delivery.
-- Rule 5A: 8 orders with NULL delivery date are excluded here
--          (they cannot be classified into a bucket).
-- ============================================================

COLUMN delivery_bucket FORMAT A15
COLUMN orders          FORMAT 9,999,999
COLUMN pct             FORMAT 990.0

SELECT
    CASE
        WHEN days_to_delivery <  7  THEN '< 7 days'
        WHEN days_to_delivery < 14  THEN '7-13 days'
        WHEN days_to_delivery < 21  THEN '14-20 days'
        WHEN days_to_delivery < 30  THEN '21-29 days'
        ELSE                             '30+ days'
    END                                                           AS delivery_bucket,
    COUNT(*)                                                       AS orders,
    ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)              AS pct
FROM fact_orders
WHERE order_status      = 'delivered'
  AND days_to_delivery IS NOT NULL
GROUP BY
    CASE
        WHEN days_to_delivery <  7  THEN '< 7 days'
        WHEN days_to_delivery < 14  THEN '7-13 days'
        WHEN days_to_delivery < 21  THEN '14-20 days'
        WHEN days_to_delivery < 30  THEN '21-29 days'
        ELSE                             '30+ days'
    END
ORDER BY MIN(days_to_delivery);


-- ============================================================
-- Q10. Repeat vs First-Time Customers
-- How many customers ordered more than once?
-- avg_lifetime_value = total spend per customer.
-- This is the loyalty insight interviewers always ask about.
-- ============================================================

COLUMN customer_type   FORMAT A15
COLUMN customers       FORMAT 9,999,999
COLUMN pct_customers   FORMAT 990.0
COLUMN total_orders    FORMAT 9,999,999
COLUMN avg_ltv         FORMAT 99,999.99

WITH customer_summary AS (
    SELECT
        fo.customer_key,
        COUNT(fo.order_id)    AS order_count,
        SUM(fo.total_revenue) AS total_spent
    FROM fact_orders fo
    WHERE fo.order_status NOT IN ('canceled', 'unavailable')
      AND fo.purchase_date_key IS NOT NULL
    GROUP BY fo.customer_key
)
SELECT
    CASE WHEN order_count = 1 THEN 'First-Time' ELSE 'Repeat' END AS customer_type,
    COUNT(*)                                                        AS customers,
    ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)               AS pct_customers,
    SUM(order_count)                                                AS total_orders,
    ROUND(AVG(total_spent), 2)                                      AS avg_ltv
FROM customer_summary
GROUP BY CASE WHEN order_count = 1 THEN 'First-Time' ELSE 'Repeat' END
ORDER BY customers DESC;

