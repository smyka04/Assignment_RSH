-- 06_baselines.sql
-- Baselines "as of" the report Monday. Only weeks before the report week are used,
-- so a backtest run for an earlier Monday never sees the future.
--
--   report_week = the Monday-to-Sunday week that just ended (as_of - 7 days)
--   lookback    = up to 8 earlier weeks (fewer at the start of the data)

CREATE OR REPLACE TABLE baselines AS
WITH
params AS (
    SELECT CAST(getvariable('as_of') - INTERVAL 7 DAY AS DATE) AS report_week
),
history AS (
    SELECT ws.*
    FROM weekly_sales ws, params
    WHERE ws.week_start <  params.report_week
      AND ws.week_start >= params.report_week - INTERVAL 56 DAY
),
usual_rank AS (   -- best weekly rank in the lookback = where the product normally sits
    SELECT platform, city, sku_code, min(avg_rank) AS usual_rank, count(*) AS history_weeks
    FROM history GROUP BY ALL
),
healthy_weeks AS (   -- weeks with normal rank and normal stock: the "what sales should be" reference
    SELECT h.*
    FROM history h
    JOIN usual_rank u USING (platform, city, sku_code)
    JOIN weekly_availability_norm n USING (week_start)
    WHERE h.avg_rank <= u.usual_rank + 1
      AND h.avg_availability >= n.norm_availability - 10
)
SELECT
    u.platform, u.city, u.sku_code, u.usual_rank, u.history_weeks,
    sum(hw.units) / nullif(sum(hw.store_days), 0)::DOUBLE AS base_units_per_store_day,
    count(hw.week_start)                                  AS healthy_weeks
FROM usual_rank u
LEFT JOIN healthy_weeks hw USING (platform, city, sku_code)
GROUP BY ALL;

-- Usual order size per warehouse x product: average of the last 4 POs that were raised.
CREATE OR REPLACE TABLE po_baselines AS
WITH params AS (SELECT CAST(getvariable('as_of') - INTERVAL 7 DAY AS DATE) AS last_po_week),
ranked AS (
    SELECT g.*, row_number() OVER (PARTITION BY warehouse_id, sku_code ORDER BY po_week DESC) AS rn
    FROM po_grid g, params
    WHERE g.po_week < params.last_po_week AND g.has_po
)
SELECT warehouse_id, sku_code, avg(qty_ordered) AS usual_qty_ordered, count(*) AS n_prior_pos
FROM ranked WHERE rn <= 4
GROUP BY ALL;
