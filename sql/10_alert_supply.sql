-- 10_alert_supply.sql
-- SUPPLY TEAM: we did not deliver enough against last Monday's purchase order.
-- Rule: fill rate of last week's PO below fill_rate_threshold for a warehouse x product.
-- Supply thinks in warehouses, products and units, so the output is in units first.

CREATE OR REPLACE TABLE alert_supply AS
WITH
params AS (SELECT CAST(getvariable('as_of') - INTERVAL 7 DAY AS DATE) AS last_week),
flagged AS (   -- every PO week below the threshold, used to find how long the problem has run
    SELECT g.*, (g.has_po AND g.fill_rate < getvariable('fill_rate_threshold')) AS low_fill
    FROM po_grid g
),
streaks AS (
    SELECT *,
           sum(CASE WHEN low_fill THEN 0 ELSE 1 END)
               OVER (PARTITION BY warehouse_id, sku_code ORDER BY po_week) AS streak_id
    FROM flagged
),
open_since AS (
    SELECT warehouse_id, sku_code, streak_id, min(po_week) AS open_since, count(*) AS weeks_open,
           sum(short_units) AS short_units_total
    FROM streaks WHERE low_fill GROUP BY ALL
),
stores_hit AS (   -- dark stores served by this warehouse that were often out of stock last week
    SELECT warehouse_id, sku_code,
           count(DISTINCT dark_store_id) FILTER (WHERE avail < 50) AS stores_below_50pct,
           count(DISTINCT dark_store_id)                           AS stores_served
    FROM (SELECT warehouse_id, sku_code, dark_store_id, avg(availability_pct) AS avail
          FROM sales, params
          WHERE week_start = params.last_week GROUP BY ALL)
    GROUP BY ALL
)
SELECT
    'Supply'                                AS team,
    'Short delivery'                        AS issue,
    s.platform, s.city, s.warehouse_id, s.sku_code,
    ws.product_name,
    s.qty_ordered, s.qty_delivered, s.short_units, s.fill_rate,
    o.open_since, o.weeks_open, o.short_units_total,
    ws.avg_availability                     AS availability_last_week,
    n.norm_availability,
    sh.stores_below_50pct, sh.stores_served,
    ws.avg_list_price,
    -- rupees: the units we did not deliver, at the price customers pay on the app
    s.short_units * ws.avg_list_price            AS inr_at_risk_week,
    -- what the stock gap already cost last week (sales lost while out of stock)
    greatest(n.norm_availability - ws.avg_availability, 0) / 100.0
        * ws.store_days * ws.units_per_available_store_day * ws.avg_list_price AS inr_lost_last_week
FROM streaks s
JOIN params ON s.po_week = params.last_week
JOIN open_since o USING (warehouse_id, sku_code, streak_id)
LEFT JOIN weekly_sales ws
       ON ws.warehouse_id = s.warehouse_id AND ws.sku_code = s.sku_code AND ws.week_start = params.last_week
LEFT JOIN weekly_availability_norm n ON n.week_start = params.last_week
LEFT JOIN stores_hit sh ON sh.warehouse_id = s.warehouse_id AND sh.sku_code = s.sku_code
WHERE s.low_fill;
