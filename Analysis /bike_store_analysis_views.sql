-- ============================================================
-- Bike Store: Business Insight Views
-- Run AFTER bike_store_data_cleaning.sql has been executed
-- ============================================================

USE bike_store;

-- 1. Monthly revenue trend with month-over-month growth (window function: LAG)
DROP VIEW IF EXISTS vw_monthly_revenue_trend;
CREATE VIEW vw_monthly_revenue_trend AS
WITH monthly AS (
    SELECT
        DATE_FORMAT(o.order_date, '%Y-%m-01') AS month_start,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS net_revenue,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY DATE_FORMAT(o.order_date, '%Y-%m-01')
)
SELECT
    month_start,
    net_revenue,
    total_orders,
    ROUND(net_revenue / total_orders, 2) AS avg_order_value,
    LAG(net_revenue) OVER (ORDER BY month_start) AS prev_month_revenue,
    ROUND(
        (net_revenue - LAG(net_revenue) OVER (ORDER BY month_start))
        / LAG(net_revenue) OVER (ORDER BY month_start) * 100, 2
    ) AS mom_growth_pct
FROM monthly;

-- 2. Category performance: revenue share and rank (window functions: SUM OVER, RANK)
DROP VIEW IF EXISTS vw_category_performance;
CREATE VIEW vw_category_performance AS
SELECT
    c.category_name,
    COUNT(DISTINCT o.order_id) AS orders_count,
    SUM(oi.quantity) AS units_sold,
    ROUND(SUM(oi.quantity * oi.list_price * (1 - oi.discount)), 2) AS net_revenue,
    RANK() OVER (ORDER BY SUM(oi.quantity * oi.list_price * (1 - oi.discount)) DESC) AS revenue_rank,
    ROUND(
        SUM(oi.quantity * oi.list_price * (1 - oi.discount))
        / SUM(SUM(oi.quantity * oi.list_price * (1 - oi.discount))) OVER () * 100, 2
    ) AS pct_of_total_revenue
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
GROUP BY c.category_name;

-- 3. Product velocity: fast vs slow movers (window functions: NTILE, DENSE_RANK, date diff for staleness)
DROP VIEW IF EXISTS vw_product_velocity;
CREATE VIEW vw_product_velocity AS
SELECT
    p.product_name,
    c.category_name,
    b.brand_name,
    SUM(oi.quantity) AS total_units_sold,
    COUNT(DISTINCT oi.order_id) AS times_ordered,
    MAX(o.order_date) AS last_sold_date,
    DATEDIFF((SELECT MAX(order_date) FROM orders), MAX(o.order_date)) AS days_since_last_sale,
    NTILE(4) OVER (ORDER BY SUM(oi.quantity) DESC) AS velocity_quartile,  -- 1 = fastest-selling quartile, 4 = slowest
    DENSE_RANK() OVER (ORDER BY SUM(oi.quantity) DESC) AS units_sold_rank
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
JOIN brands b ON b.brand_id = p.brand_id
GROUP BY p.product_name, c.category_name, b.brand_name;

-- 4. Customer RFM segmentation: who is a loyal customer vs at risk of churn (CTE + NTILE)
DROP VIEW IF EXISTS vw_customer_rfm;
CREATE VIEW vw_customer_rfm AS
WITH customer_orders AS (
    SELECT
        cu.customer_id,
        CONCAT(cu.first_name, ' ', cu.last_name) AS customer_name,
        cu.state,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS monetary,
        DATEDIFF((SELECT MAX(order_date) FROM orders), MAX(o.order_date)) AS recency_days
    FROM customers cu
    JOIN orders o ON o.customer_id = cu.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY cu.customer_id, cu.first_name, cu.last_name, cu.state
)
SELECT
    customer_id,
    customer_name,
    state,
    frequency,
    ROUND(monetary, 2) AS monetary,
    recency_days,
    NTILE(4) OVER (ORDER BY recency_days ASC) AS recency_score,     -- 1 = most recent
    NTILE(4) OVER (ORDER BY frequency DESC) AS frequency_score,     -- 1 = most frequent
    NTILE(4) OVER (ORDER BY monetary DESC) AS monetary_score,       -- 1 = highest spender
    CASE
        WHEN frequency = 1 THEN 'One-Time Buyer'
        WHEN frequency > 1 AND recency_days <= 180 THEN 'Active Repeat Customer'
        WHEN frequency > 1 AND recency_days > 180 THEN 'At-Risk Repeat Customer'
    END AS customer_segment
FROM customer_orders;

-- 5. Customer retention summary: repeat purchase rate, a core stakeholder question (CTE + aggregate)
DROP VIEW IF EXISTS vw_customer_retention_summary;
CREATE VIEW vw_customer_retention_summary AS
WITH order_counts AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS order_count
    FROM orders
    GROUP BY customer_id
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN order_count = 1 THEN 1 ELSE 0 END) AS one_time_customers,
    SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS retention_rate_pct
FROM order_counts;

-- 6. Discount effectiveness: does discounting actually move more units? (CASE buckets + aggregate)
DROP VIEW IF EXISTS vw_discount_effectiveness;
CREATE VIEW vw_discount_effectiveness AS
SELECT
    CASE
        WHEN discount = 0 THEN 'No Discount'
        WHEN discount <= 0.10 THEN 'Low (1-10%)'
        WHEN discount <= 0.20 THEN 'Medium (11-20%)'
        ELSE 'High (20%+)'
    END AS discount_band,
    COUNT(*) AS line_items,
    SUM(quantity) AS total_units_sold,
    ROUND(AVG(quantity), 2) AS avg_units_per_order_line,
    ROUND(SUM(quantity * list_price * (1 - discount)), 2) AS net_revenue
FROM order_items
GROUP BY discount_band
ORDER BY discount_band;

-- 7. Store & staff performance: which locations/people drive revenue (window function: RANK)
DROP VIEW IF EXISTS vw_store_staff_performance;
CREATE VIEW vw_store_staff_performance AS
SELECT
    s.store_name,
    st.state AS store_state,
    CONCAT(sf.first_name, ' ', sf.last_name) AS staff_name,
    COUNT(DISTINCT o.order_id) AS orders_handled,
    ROUND(SUM(oi.quantity * oi.list_price * (1 - oi.discount)), 2) AS net_revenue,
    RANK() OVER (PARTITION BY s.store_name ORDER BY SUM(oi.quantity * oi.list_price * (1 - oi.discount)) DESC) AS rank_within_store
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN staffs sf ON sf.staff_id = o.staff_id
JOIN stores s ON s.store_id = o.store_id
JOIN stores st ON st.store_id = s.store_id
GROUP BY s.store_name, st.state, sf.first_name, sf.last_name;

-- 8. Order fulfillment: are we shipping late, and does it vary by store? (DATEDIFF)
DROP VIEW IF EXISTS vw_order_fulfillment;
CREATE VIEW vw_order_fulfillment AS
SELECT
    s.store_name,
    o.order_id,
    osl.status_name,
    o.required_date,
    o.shipped_date,
    DATEDIFF(o.shipped_date, o.required_date) AS days_late,
    CASE WHEN o.shipped_date IS NULL THEN 'Not Shipped'
         WHEN o.shipped_date > o.required_date THEN 'Late'
         ELSE 'On Time' END AS fulfillment_status
FROM orders o
JOIN stores s ON s.store_id = o.store_id
JOIN order_status_lookup osl ON osl.status_id = o.order_status;

-- 9. Order status funnel: pending / processing / rejected / completed split (business health check)
DROP VIEW IF EXISTS vw_order_status_funnel;
CREATE VIEW vw_order_status_funnel AS
SELECT
    osl.status_name,
    COUNT(*) AS order_count,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM orders) * 100, 2) AS pct_of_all_orders
FROM orders o
JOIN order_status_lookup osl ON osl.status_id = o.order_status
GROUP BY osl.status_name;

-- 10. Stock risk: compares current stock to recent sales velocity to flag over/under-stock
DROP VIEW IF EXISTS vw_stock_risk;
CREATE VIEW vw_stock_risk AS
WITH recent_sales AS (
    SELECT oi.product_id, SUM(oi.quantity) AS units_sold_last_90_days
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_date >= (SELECT DATE_SUB(MAX(order_date), INTERVAL 90 DAY) FROM orders)
    GROUP BY oi.product_id
)
SELECT
    st.store_id,
    s.store_name,
    p.product_name,
    st.quantity AS current_stock,
    COALESCE(rs.units_sold_last_90_days, 0) AS units_sold_last_90_days,
    CASE
        WHEN st.quantity = 0 THEN 'Out of Stock'
        WHEN COALESCE(rs.units_sold_last_90_days, 0) = 0 AND st.quantity > 0 THEN 'Slow-Moving / Overstocked'
        WHEN st.quantity < COALESCE(rs.units_sold_last_90_days, 0) THEN 'Understocked Risk'
        ELSE 'Healthy'
    END AS stock_status
FROM stocks st
JOIN stores s ON s.store_id = st.store_id
JOIN products p ON p.product_id = st.product_id
LEFT JOIN recent_sales rs ON rs.product_id = st.product_id;

-- 11. Top and bottom 5 products by revenue, side by side (window function: ROW_NUMBER via UNION)
DROP VIEW IF EXISTS vw_top_bottom_products;
CREATE VIEW vw_top_bottom_products AS
WITH product_revenue AS (
    SELECT
        p.product_name,
        ROUND(SUM(oi.quantity * oi.list_price * (1 - oi.discount)), 2) AS net_revenue
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    GROUP BY p.product_name
),
ranked AS (
    SELECT product_name, net_revenue,
        ROW_NUMBER() OVER (ORDER BY net_revenue DESC) AS top_rank,
        ROW_NUMBER() OVER (ORDER BY net_revenue ASC) AS bottom_rank
    FROM product_revenue
)
SELECT 'Top 5' AS category, product_name, net_revenue FROM ranked WHERE top_rank <= 5
UNION ALL
SELECT 'Bottom 5' AS category, product_name, net_revenue FROM ranked WHERE bottom_rank <= 5;

-- 12. Revenue by customer geography (state-level, for regional strategy questions)
DROP VIEW IF EXISTS vw_revenue_by_state;
CREATE VIEW vw_revenue_by_state AS
SELECT
    cu.state,
    COUNT(DISTINCT cu.customer_id) AS customers,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(oi.quantity * oi.list_price * (1 - oi.discount)), 2) AS net_revenue,
    ROUND(SUM(oi.quantity * oi.list_price * (1 - oi.discount)) / COUNT(DISTINCT cu.customer_id), 2) AS revenue_per_customer
FROM customers cu
JOIN orders o ON o.customer_id = cu.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY cu.state
ORDER BY net_revenue DESC;
