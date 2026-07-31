# 🚲 Bike Store SQL Analysis

End-to-end MySQL analysis of a 3-year multi-store bike retailer dataset (Jan 2016 – Apr 2018) — 1,445 customers, 1,615 orders, 321 products, and 3 stores across California, New York, and Texas.

The goal of this project was not just to write queries, but to answer the questions a business stakeholder actually asks: *why is revenue moving the way it is, why are customers not coming back, which products are worth restocking, and is our discount strategy working.*

> **Dataset note:** This uses the publicly available "BikeStores" sample dataset, commonly used for SQL practice. All cleaning, view design, and business insights below are original analysis performed on top of it.

---

## 🔍 Key Findings

**1. Customer retention is low — a real problem, not a minor stat**
Only **9.07%** of customers (131 of 1,445) ever placed a second order. Over 90% of the customer base was acquired once and never returned, which points to an acquisition-heavy, retention-light business model with no visible loyalty or win-back mechanism.

![Customer Retention Summary](Screenshot/01_customer_retention.png)

**2. Revenue is concentrated in one category, but not the one that sells the most units**
Mountain Bikes generate **35.31%** of total revenue ($2.72M) despite Cruisers Bicycles moving more total units (2,063 vs. 1,755). This is a classic volume-vs-price-mix gap — Mountain Bikes carry a materially higher price point, so unit volume alone is a misleading measure of category importance.

![Category Performance](Screenshot/02_category_performance.png)

**3. Revenue trended upward through mid-2017, then the data collection window ends**
Monthly revenue climbed from ~$215K (Jan 2016) to a peak of **$378,865** in June 2017, with real month-to-month volatility along the way (swings of ±20–40%). From May 2018 onward, order volume collapses to 1–4 orders/month — this is almost certainly the dataset's collection cutoff rather than a genuine business collapse, and the trend analysis is scoped accordingly to Jan 2016–Apr 2018.

![Monthly Revenue Trend](Screenshot/03_monthly_revenue_trend.png)

**4. The "worst performing" products are mostly 2018 models — likely the same cutoff, not weak products**
4 of the 5 lowest-revenue products are 2018 model-year bikes, each with well under $260 in lifetime revenue. Given finding #3, these products simply didn't get enough time on the market before the data window closed — they shouldn't be read as underperformers without that context.

![Top 5 vs Bottom 5 Products](Screenshot/04_top_bottom_products.png)

**5. Discounting is not moving volume**
Across both discount bands present in the data (Low 1–10%, Medium 11–20%), the average units sold per order line is identical at **1.50** — discounting deeper had zero measurable effect on how much customers bought. This suggests current discounts are functioning as margin erosion rather than a real demand driver, and are worth revisiting.

![Discount Effectiveness](Screenshot/05_discount_effectiveness.png)

---

## 🗂️ Database Schema

9 relational tables — customers and orders on one side, products/stocks/brands/categories on the other, joined through `order_items` as the central fact table.

![Bike Store ERD](Screenshot/06_erd_schema.png)

---

## 🛠️ What This Project Covers

**Data Cleaning**
- Corrected fields where missing values were stored as the literal text `'NULL'` instead of a true SQL NULL (`customers.phone`, `staffs.manager_id`, `orders.shipped_date`)
- Retyped `manager_id` to `BIGINT` and `shipped_date` to `DATE` after cleanup, enabling proper joins and date arithmetic
- Trimmed stray whitespace from address and name fields
- Replaced raw numeric order-status codes (1–4) with a readable lookup table

**12 Business-Insight Views**
Built using window functions, CTEs, and date functions — not just flat aggregates:

| View | Business Question Answered |
|---|---|
| `vw_monthly_revenue_trend` | Is revenue growing or shrinking, and by how much month over month? |
| `vw_category_performance` | Which product categories actually drive revenue? |
| `vw_product_velocity` | Which products are fast movers vs. slow movers? |
| `vw_customer_rfm` | Who are our most valuable customers, and who's at risk of churning? |
| `vw_customer_retention_summary` | What share of customers ever come back? |
| `vw_discount_effectiveness` | Does discounting actually increase how much customers buy? |
| `vw_store_staff_performance` | Which stores and staff are driving the most revenue? |
| `vw_order_fulfillment` | Are orders shipping on time, and where are the delays? |
| `vw_order_status_funnel` | What share of orders are pending, rejected, or completed? |
| `vw_stock_risk` | Which products are over- or under-stocked relative to recent demand? |
| `vw_top_bottom_products` | Which products are the best and worst revenue performers? |
| `vw_revenue_by_state` | How does performance vary by customer geography? |

**Techniques used:** `LAG()`, `RANK()`, `DENSE_RANK()`, `NTILE()`, `ROW_NUMBER()`, CTEs (`WITH`), `DATEDIFF`, `DATE_FORMAT`, `CASE`-based segmentation, correlated subqueries, and multi-table joins across a 9-table relational schema.

**Sample — Customer RFM Segmentation** (CTE + window functions, used to power finding #1 above):

```sql
WITH customer_orders AS (
    SELECT
        cu.customer_id,
        CONCAT(cu.first_name, ' ', cu.last_name) AS customer_name,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS monetary,
        DATEDIFF((SELECT MAX(order_date) FROM orders), MAX(o.order_date)) AS recency_days
    FROM customers cu
    JOIN orders o ON o.customer_id = cu.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY cu.customer_id, cu.first_name, cu.last_name
)
SELECT
    customer_id, customer_name, frequency, monetary, recency_days,
    NTILE(4) OVER (ORDER BY recency_days ASC)  AS recency_score,
    NTILE(4) OVER (ORDER BY frequency DESC)    AS frequency_score,
    NTILE(4) OVER (ORDER BY monetary DESC)     AS monetary_score,
    CASE
        WHEN frequency = 1 THEN 'One-Time Buyer'
        WHEN frequency > 1 AND recency_days <= 180 THEN 'Active Repeat Customer'
        WHEN frequency > 1 AND recency_days > 180 THEN 'At-Risk Repeat Customer'
    END AS customer_segment
FROM customer_orders;
```

Full logic for all 12 views is in [`Analysis/bike_store_analysis_views.sql`](Analysis/bike_store_analysis_views.sql). Cleaning steps are in [`Analysis/bike_store_data_cleaning.sql`](Analysis/bike_store_data_cleaning.sql).

---

## 📁 Repository Structure

```
bike-store-sql-analysis/
├── Raw_File/
│   └── bike_store_combined.sql          ← Raw data import (9 tables, ~10,500 rows)
├── Analysis/
│   ├── bike_store_data_cleaning.sql     ← Data cleaning (NULL fixes, type corrections, status lookup)
│   └── bike_store_analysis_views.sql    ← 12 business-insight views
├── Screenshot/
│   ├── 01_customer_retention.png
│   ├── 02_category_performance.png
│   ├── 03_monthly_revenue_trend.png
│   ├── 04_top_bottom_products.png
│   ├── 05_discount_effectiveness.png
│   └── 06_erd_schema.png
└── README.md
```

## ▶️ How to Run

1. Execute `Raw_File/bike_store_combined.sql` — creates the `bike_store` database and loads all 9 raw tables
2. Execute `Analysis/bike_store_data_cleaning.sql` — fixes data quality issues and adds the status lookup table
3. Execute `Analysis/bike_store_analysis_views.sql` — builds all 12 analytical views
4. Query any view directly, e.g.:
   ```sql
   SELECT * FROM vw_customer_retention_summary;
   ```

## 🧰 Tools

MySQL 8.0 · Window Functions · Common Table Expressions · Views · MySQL Workbench

---

## 👤 About

Part of a self-built 12-project data analytics portfolio spanning Excel, SQL, Power BI, and Python.
Full portfolio: [github.com/hiten-ux](https://github.com/hiten-ux)
