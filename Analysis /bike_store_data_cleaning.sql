-- ============================================================
-- Bike Store: Data Cleaning
-- Run AFTER bike_store_combined.sql has been executed
-- Run BEFORE bike_store_analysis_views.sql
-- ============================================================

USE bike_store;

-- Workbench blocks UPDATEs without a WHERE on a key column by default; disable for this session
SET SQL_SAFE_UPDATES = 0;

-- 1a. Trim stray whitespace in text fields (e.g. addresses had trailing spaces)
UPDATE customers SET street = TRIM(street), city = TRIM(city), first_name = TRIM(first_name), last_name = TRIM(last_name);
UPDATE stores SET street = TRIM(street), city = TRIM(city);
UPDATE products SET product_name = TRIM(product_name);
UPDATE staffs SET first_name = TRIM(first_name), last_name = TRIM(last_name);

-- 1b. Convert the literal text 'NULL' into a real NULL (customers.phone: ~88% affected)
UPDATE customers SET phone = NULL WHERE phone = 'NULL';

-- 1c. Fix staffs.manager_id: stored as text with 'NULL' string; convert then retype to BIGINT for hierarchy joins
UPDATE staffs SET manager_id = NULL WHERE manager_id = 'NULL';
ALTER TABLE staffs MODIFY COLUMN manager_id BIGINT NULL DEFAULT NULL;

-- 1d. Fix orders.shipped_date: stored as text with 'NULL' string for unshipped orders; convert then retype to DATE
UPDATE orders SET shipped_date = NULL WHERE shipped_date = 'NULL';
ALTER TABLE orders MODIFY COLUMN shipped_date DATE NULL DEFAULT NULL;

-- 1e. Replace magic-number order_status with a readable lookup table
DROP TABLE IF EXISTS order_status_lookup;
CREATE TABLE order_status_lookup (
  status_id INT PRIMARY KEY,
  status_name VARCHAR(20) NOT NULL
);
INSERT INTO order_status_lookup VALUES (1,'Pending'),(2,'Processing'),(3,'Rejected'),(4,'Completed');

-- 1f. Net line revenue is used across all views; keep the formula consistent everywhere
--     net_revenue = quantity * list_price * (1 - discount)

-- Re-enable safe update mode now that cleaning is done
SET SQL_SAFE_UPDATES = 1;
