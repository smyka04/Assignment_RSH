-- 02_clean.sql
-- Clean and join the raw tables into one analysis-ready daily fact table.
--   * trims stray spaces in every text key
--   * maps the 11 city spellings to 6 cities (Eshan confirmed the merges)
--   * drops exact duplicate rows in daily_sales
--   * adds week_start (Monday) to sales and POs

CREATE OR REPLACE MACRO clean_city(c) AS
    CASE lower(trim(c))
        WHEN 'bangalore' THEN 'Bengaluru'
        WHEN 'bengaluru' THEN 'Bengaluru'
        WHEN 'delhi'     THEN 'Delhi NCR'
        WHEN 'new delhi' THEN 'Delhi NCR'
        WHEN 'delhi ncr' THEN 'Delhi NCR'
        WHEN 'hyderabad' THEN 'Hyderabad'
        WHEN 'mumbai'    THEN 'Mumbai'
        WHEN 'pune'      THEN 'Pune'
        WHEN 'kolkata'   THEN 'Kolkata'
        ELSE trim(c)     -- unknown spelling: kept as-is and reported by 03_data_quality.sql
    END;

CREATE OR REPLACE TABLE dark_stores AS
SELECT
    trim(dark_store_id)  AS dark_store_id,
    trim(platform)       AS platform,
    clean_city(city)     AS city,
    trim(city)           AS city_raw,
    trim(pincode)        AS pincode,
    trim(warehouse_id)   AS warehouse_id,
    opened_date
FROM raw_dark_stores;

CREATE OR REPLACE TABLE products AS
SELECT
    trim(platform)            AS platform,
    trim(platform_product_id) AS platform_product_id,
    trim(sku_code)            AS sku_code,
    trim(product_name)        AS product_name,
    trim(category)            AS category,
    trim(pack_size)           AS pack_size,
    mrp_inr
FROM raw_products;

-- One city per warehouse (each warehouse supplies stores in exactly one city).
CREATE OR REPLACE TABLE warehouses AS
SELECT warehouse_id, platform, any_value(city) AS city, count(*) AS n_stores
FROM dark_stores
GROUP BY ALL;

CREATE OR REPLACE TABLE sales AS
WITH dedup AS (
    SELECT DISTINCT
        date,
        trim(platform)            AS platform,
        trim(dark_store_id)       AS dark_store_id,
        trim(platform_product_id) AS platform_product_id,
        availability_pct, units_sold, selling_price_inr, sales_inr, search_rank
    FROM raw_daily_sales
)
SELECT
    d.date,
    CAST(date_trunc('week', d.date) AS DATE) AS week_start,   -- ISO week: Monday
    d.platform,
    s.city,
    s.warehouse_id,
    d.dark_store_id,
    s.opened_date,
    p.sku_code,
    p.product_name,
    p.category,
    p.mrp_inr,
    d.platform_product_id,
    d.availability_pct,
    d.units_sold,
    d.selling_price_inr,
    d.sales_inr,
    d.search_rank
FROM dedup d
JOIN dark_stores s USING (dark_store_id)
JOIN products   p ON p.platform = d.platform AND p.platform_product_id = d.platform_product_id;

CREATE OR REPLACE TABLE purchase_orders AS
SELECT
    trim(po.po_id)        AS po_id,
    po.po_date,
    CAST(date_trunc('week', po.po_date) AS DATE) AS week_start,
    trim(po.platform)     AS platform,
    trim(po.warehouse_id) AS warehouse_id,
    w.city,
    trim(po.sku_code)     AS sku_code,
    po.qty_ordered,
    po.qty_delivered,
    po.delivery_date,
    po.qty_delivered / po.qty_ordered::DOUBLE      AS fill_rate,
    datediff('day', po.po_date, po.delivery_date) AS days_to_deliver
FROM raw_purchase_orders po
LEFT JOIN warehouses w ON w.warehouse_id = trim(po.warehouse_id);
