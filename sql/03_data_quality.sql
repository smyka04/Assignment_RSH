-- 03_data_quality.sql
-- Count every data problem found, measured on the RAW tables, and say what we did about it.
-- The page and the note read from dq_checks.

CREATE OR REPLACE TABLE dq_checks AS
WITH
dup_rows AS (
    SELECT count(*) - count(DISTINCT (date, platform, dark_store_id, platform_product_id,
                                      availability_pct, units_sold, selling_price_inr, sales_inr, search_rank)) AS n
    FROM raw_daily_sales
),
dup_keys_conflicting AS (   -- same store / product / day but different numbers
    SELECT count(*) AS n FROM (
        SELECT date, dark_store_id, platform_product_id
        FROM (SELECT DISTINCT * FROM raw_daily_sales)
        GROUP BY ALL HAVING count(*) > 1)
),
city_spellings AS (
    SELECT count(DISTINCT city) AS raw_n,
           count(DISTINCT clean_city(city)) AS clean_n,
           string_agg(DISTINCT '"' || city || '"', ', ' ORDER BY '"' || city || '"') AS spellings
    FROM raw_dark_stores
),
new_stores AS (
    SELECT count(*) AS n
    FROM raw_dark_stores
    WHERE opened_date > (SELECT min(date) FROM raw_daily_sales)
),
unmapped_products AS (
    SELECT count(*) AS n FROM raw_daily_sales d
    WHERE NOT EXISTS (SELECT 1 FROM raw_products p
                      WHERE p.platform = d.platform AND p.platform_product_id = d.platform_product_id)
),
unmapped_stores AS (
    SELECT count(*) AS n FROM raw_daily_sales d
    WHERE NOT EXISTS (SELECT 1 FROM raw_dark_stores s WHERE s.dark_store_id = d.dark_store_id)
),
sales_before_open AS (
    SELECT count(*) AS n FROM raw_daily_sales d JOIN raw_dark_stores s USING (dark_store_id)
    WHERE d.date < s.opened_date
),
bad_sales_math AS (
    SELECT count(*) AS n FROM raw_daily_sales
    WHERE abs(units_sold * selling_price_inr - sales_inr) > 0.5
),
bad_availability AS (
    SELECT count(*) AS n FROM raw_daily_sales WHERE availability_pct < 0 OR availability_pct > 100
),
sold_while_unavailable AS (
    SELECT count(*) AS n FROM raw_daily_sales WHERE availability_pct = 0 AND units_sold > 0
),
price_above_mrp AS (
    SELECT count(*) AS n FROM raw_daily_sales d JOIN raw_products p USING (platform, platform_product_id)
    WHERE d.selling_price_inr > p.mrp_inr
),
rank_outliers AS (
    SELECT count(*) AS n,
           string_agg(DISTINCT d.platform || ' ' || clean_city(s.city) || ' ' || p.sku_code, '; ') AS where_
    FROM raw_daily_sales d
    JOIN raw_dark_stores s ON s.dark_store_id = d.dark_store_id
    JOIN raw_products p ON p.platform = d.platform AND p.platform_product_id = d.platform_product_id
    WHERE d.search_rank > 10
),
po_weeks AS (SELECT DISTINCT po_date FROM raw_purchase_orders),
po_pairs AS (SELECT DISTINCT warehouse_id, sku_code FROM raw_purchase_orders),
missing_po AS (
    SELECT count(*) AS n,
           string_agg(g.warehouse_id || ' ' || g.sku_code || ' ' || strftime(g.po_date, '%d %b'), '; '
                      ORDER BY g.po_date, g.warehouse_id, g.sku_code) AS detail
    FROM (SELECT * FROM po_weeks, po_pairs) g
    LEFT JOIN raw_purchase_orders po USING (po_date, warehouse_id, sku_code)
    WHERE po.po_id IS NULL
),
over_delivered AS (
    SELECT count(*) AS n FROM raw_purchase_orders WHERE qty_delivered > qty_ordered
),
po_dup AS (
    SELECT count(*) - count(DISTINCT (po_date, warehouse_id, sku_code)) AS n FROM raw_purchase_orders
),
store_day_gaps AS (   -- an open store should report every product every day
    SELECT count(*) AS n FROM (
        SELECT dark_store_id, count(DISTINCT date) AS n_days,
               datediff('day', min(date), max(date)) + 1 AS span
        FROM raw_daily_sales GROUP BY 1) WHERE n_days <> span
)
SELECT * FROM (VALUES
  (1, 'Exact duplicate rows in daily_sales',
      (SELECT n FROM dup_rows), 'Rows repeated in full',
      'Dropped the copies (SELECT DISTINCT). Otherwise units and rupees are double counted.'),
  (2, 'Duplicate store/product/day with different numbers',
      (SELECT n FROM dup_keys_conflicting), 'Same key, conflicting values',
      'None found, so no rule needed to pick one.'),
  (3, 'Inconsistent city names',
      (SELECT raw_n FROM city_spellings), (SELECT spellings FROM city_spellings),
      'Trimmed and mapped to 6 cities: Bangalore = Bengaluru; Delhi / New Delhi = Delhi NCR; HYDERABAD = Hyderabad; "mumbai " = Mumbai.'),
  (4, 'Dark stores that opened during the 10 weeks',
      (SELECT n FROM new_stores), 'Store count grows week to week',
      'Compared sales per store-day, not totals, so new stores do not look like growth.'),
  (5, 'Search rank above 10',
      (SELECT n FROM rank_outliers), (SELECT where_ FROM rank_outliers),
      'Kept. Not an error: it is the Zepto Bengaluru search-rank drop (problem 2).'),
  (6, 'Missing weekly purchase orders',
      (SELECT n FROM missing_po), (SELECT detail FROM missing_po),
      'Kept as a signal: built a full warehouse x product x week grid so a missing PO becomes a row.'),
  (7, 'Product ids that would break if read as numbers',
      (SELECT count(*) FROM raw_products WHERE NOT regexp_full_match(platform_product_id, '[1-9][0-9]*')),
      'Instamart ids have leading zeros (IM062962); Zepto ids end in X',
      'Read every id as text so leading zeros are not lost.'),
  (8, 'Sales rows with no product mapping',  (SELECT n FROM unmapped_products), '', 'None found.'),
  (9, 'Sales rows with no store mapping',    (SELECT n FROM unmapped_stores),   '', 'None found.'),
  (10, 'Sales before the store opened',      (SELECT n FROM sales_before_open), '', 'None found.'),
  (11, 'sales_inr not equal to units x price', (SELECT n FROM bad_sales_math),  '', 'None found.'),
  (12, 'Availability outside 0-100%',        (SELECT n FROM bad_availability),  '', 'None found.'),
  (13, 'Units sold while availability was 0%', (SELECT n FROM sold_while_unavailable), '', 'None found.'),
  (14, 'Selling price above MRP',            (SELECT n FROM price_above_mrp),   '', 'None found.'),
  (15, 'Delivered more than ordered',        (SELECT n FROM over_delivered),    '', 'None found.'),
  (16, 'Duplicate purchase orders',          (SELECT n FROM po_dup),            '', 'None found.'),
  (17, 'Stores with missing days',           (SELECT n FROM store_day_gaps),    '', 'None found.')
) AS t(check_id, check_name, n_found, detail, what_we_did);
