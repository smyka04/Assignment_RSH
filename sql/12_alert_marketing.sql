-- 12_alert_marketing.sql
-- MARKETING: a product has slipped down the app's search results while stock was fine,
-- so customers stop finding it. Candidate for ads / sponsored listings.
-- Rule: last week's average rank is at least rank_drop_places worse than its usual rank,
-- availability is near normal (so it is not a stock problem), and sales per store-day fell.

CREATE OR REPLACE TABLE alert_marketing AS
WITH
params AS (SELECT CAST(getvariable('as_of') - INTERVAL 7 DAY AS DATE) AS last_week),
weeks AS (
    SELECT ws.*, b.usual_rank, b.base_units_per_store_day,
           ws.avg_rank >= b.usual_rank + getvariable('rank_drop_places') AS rank_down
    FROM weekly_sales ws
    JOIN baselines b USING (platform, city, sku_code)
),
streaks AS (
    SELECT *,
           sum(CASE WHEN rank_down THEN 0 ELSE 1 END)
               OVER (PARTITION BY platform, city, sku_code ORDER BY week_start) AS streak_id
    FROM weeks
),
runs AS (
    SELECT platform, city, sku_code, streak_id, min(week_start) AS open_since, count(*) AS weeks_open
    FROM streaks WHERE rank_down GROUP BY ALL
)
SELECT
    'Marketing'                    AS team,
    'Search rank drop'             AS issue,
    s.platform, s.city, s.warehouse_id, s.sku_code, s.product_name,
    r.open_since, r.weeks_open,
    s.usual_rank, s.avg_rank       AS rank_last_week,
    s.avg_availability             AS availability_last_week,
    n.norm_availability,
    s.base_units_per_store_day, s.units_per_store_day,
    s.avg_list_price,
    (s.base_units_per_store_day - s.units_per_store_day) * s.store_days * s.avg_list_price AS inr_lost_last_week,
    (s.base_units_per_store_day - s.units_per_store_day) * s.store_days * s.avg_list_price AS inr_at_risk_week
FROM streaks s
JOIN params ON s.week_start = params.last_week
JOIN runs r USING (platform, city, sku_code, streak_id)
JOIN weekly_availability_norm n USING (week_start)
WHERE s.rank_down
  AND s.avg_availability >= n.norm_availability - 10
  AND s.units_per_store_day < s.base_units_per_store_day;
