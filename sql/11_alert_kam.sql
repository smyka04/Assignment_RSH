-- 11_alert_kam.sql
-- PLATFORM ACCOUNT MANAGERS (KAM), one list per platform.
--  (a) PO stopped: a warehouse that normally orders a product raised no PO last Monday.
--      Flagged in the first week, before the dark stores run dry.
--  (b) Unexplained stock-out: availability far below normal across a city while our
--      deliveries were fine. Points at a platform-side problem (listing, inbound, transfer).

CREATE OR REPLACE TABLE alert_kam AS
WITH
params AS (SELECT CAST(getvariable('as_of') - INTERVAL 7 DAY AS DATE) AS last_week),
streaks AS (
    SELECT *,
           sum(CASE WHEN has_po THEN 1 ELSE 0 END)
               OVER (PARTITION BY warehouse_id, sku_code ORDER BY po_week) AS streak_id
    FROM po_grid
),
missing_runs AS (
    SELECT warehouse_id, sku_code, streak_id, min(po_week) AS open_since, count(*) AS weeks_open
    FROM streaks WHERE NOT has_po GROUP BY ALL
),
po_stopped AS (
    SELECT
        'KAM'                              AS team,
        'PO stopped'                       AS issue,
        s.platform, s.city, s.warehouse_id, s.sku_code, ws.product_name,
        m.open_since, m.weeks_open,
        b.usual_qty_ordered,
        ws.avg_availability                AS availability_last_week,
        n.norm_availability,
        ws.avg_list_price,
        -- rupees: one normal week of orders that will not reach the shelves
        b.usual_qty_ordered * ws.avg_list_price AS inr_at_risk_week,
        greatest(n.norm_availability - ws.avg_availability, 0) / 100.0
            * ws.store_days * ws.units_per_available_store_day * ws.avg_list_price AS inr_lost_last_week
    FROM streaks s
    JOIN params ON s.po_week = params.last_week
    JOIN missing_runs m USING (warehouse_id, sku_code, streak_id)
    JOIN po_baselines b USING (warehouse_id, sku_code)      -- must have ordered before
    LEFT JOIN weekly_sales ws
           ON ws.warehouse_id = s.warehouse_id AND ws.sku_code = s.sku_code AND ws.week_start = params.last_week
    LEFT JOIN weekly_availability_norm n ON n.week_start = params.last_week
    WHERE NOT s.has_po
),
supply_cause AS (   -- a short or missing PO in the last 2 weeks already explains a stock-out
    SELECT DISTINCT warehouse_id, sku_code
    FROM po_grid, params
    WHERE po_week >= params.last_week - INTERVAL 7 DAY
      AND (NOT has_po OR fill_rate < getvariable('fill_rate_threshold'))
),
unexplained AS (
    SELECT
        'KAM'                              AS team,
        'Stock-out, deliveries fine'       AS issue,
        ws.platform, ws.city, ws.warehouse_id, ws.sku_code, ws.product_name,
        params.last_week                   AS open_since, 1 AS weeks_open,
        NULL::DOUBLE                       AS usual_qty_ordered,
        ws.avg_availability                AS availability_last_week,
        n.norm_availability,
        ws.avg_list_price,
        (n.norm_availability - ws.avg_availability) / 100.0
            * ws.store_days * ws.units_per_available_store_day * ws.avg_list_price AS inr_at_risk_week,
        (n.norm_availability - ws.avg_availability) / 100.0
            * ws.store_days * ws.units_per_available_store_day * ws.avg_list_price AS inr_lost_last_week
    FROM weekly_sales ws
    JOIN params ON ws.week_start = params.last_week
    JOIN weekly_availability_norm n USING (week_start)
    WHERE ws.avg_availability < n.norm_availability - getvariable('availability_gap_pts')
      AND NOT EXISTS (SELECT 1 FROM supply_cause c
                      WHERE c.warehouse_id = ws.warehouse_id AND c.sku_code = ws.sku_code)
)
SELECT * FROM po_stopped
UNION ALL BY NAME
SELECT * FROM unexplained;
