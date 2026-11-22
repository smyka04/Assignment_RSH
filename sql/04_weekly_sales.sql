-- 04_weekly_sales.sql
-- Weekly sales by platform x city x warehouse x product, using only data before the report Monday (as_of).
-- Each platform has one warehouse per city, so warehouse_id is carried along for the supply team.
-- Everything is also expressed per store-day, so new stores opening do not look like growth.

CREATE OR REPLACE TABLE weekly_sales AS
SELECT
    platform, city, warehouse_id, sku_code,
    any_value(product_name)                         AS product_name,
    any_value(category)                             AS category,
    week_start,
    count(*)                                        AS store_days,
    count(DISTINCT dark_store_id)                   AS n_stores,
    sum(units_sold)                                 AS units,
    sum(sales_inr)                                  AS sales_inr,
    avg(availability_pct)                           AS avg_availability,
    avg(search_rank)                                AS avg_rank,
    sum(sales_inr) / nullif(sum(units_sold), 0)     AS avg_price,
    avg(selling_price_inr)                          AS avg_list_price,
    sum(units_sold) / count(*)::DOUBLE              AS units_per_store_day,
    -- units per store-day while in stock: strips out stock-outs, used for lost-sales estimates
    sum(units_sold) / nullif(sum(availability_pct) / 100.0, 0) AS units_per_available_store_day
FROM sales
WHERE date < getvariable('as_of')
GROUP BY platform, city, warehouse_id, sku_code, week_start;

-- What "normal" availability looks like in a given week: the median across every
-- platform x city x product. A peer benchmark does not drift when one city has a
-- long-running problem, unlike that city's own trailing average.
CREATE OR REPLACE TABLE weekly_availability_norm AS
SELECT week_start, median(avg_availability) AS norm_availability
FROM weekly_sales
GROUP BY week_start;
