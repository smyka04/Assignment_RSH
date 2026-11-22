-- 05_weekly_po.sql
-- Purchase orders on a full grid: every warehouse x product x PO Monday up to the report date.
-- A PO that was never raised shows up as a row with has_po = false, instead of silently not existing.

CREATE OR REPLACE TABLE po_grid AS
WITH
po_mondays AS (
    SELECT CAST(range AS DATE) AS po_week
    FROM range((SELECT min(week_start) FROM purchase_orders),
               getvariable('as_of'),            -- POs raised before the report Monday
               INTERVAL 7 DAY)
),
pairs AS (   -- every warehouse x product the platform has ever ordered
    SELECT DISTINCT p.platform, p.warehouse_id, w.city, p.sku_code
    FROM purchase_orders p JOIN warehouses w USING (warehouse_id)
    WHERE p.po_date < getvariable('as_of')
)
SELECT
    pr.platform, pr.city, pr.warehouse_id, pr.sku_code, m.po_week,
    po.po_id IS NOT NULL                    AS has_po,
    coalesce(po.qty_ordered, 0)             AS qty_ordered,
    coalesce(po.qty_delivered, 0)           AS qty_delivered,
    coalesce(po.qty_ordered - po.qty_delivered, 0) AS short_units,
    po.fill_rate,
    po.delivery_date,
    po.days_to_deliver
FROM pairs pr
CROSS JOIN po_mondays m
LEFT JOIN purchase_orders po
       ON po.warehouse_id = pr.warehouse_id
      AND po.sku_code     = pr.sku_code
      AND po.week_start   = m.po_week;
