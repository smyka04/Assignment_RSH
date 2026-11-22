-- 20_rank_alerts.sql
-- Put all alerts in one list, biggest rupee impact first, and cut the noise:
--   * drop anything worth less than min_inr_at_risk a week
--   * keep at most max_alerts_per_team per team

CREATE OR REPLACE TABLE alerts AS
WITH all_alerts AS (
    SELECT * FROM alert_supply
    UNION ALL BY NAME SELECT * FROM alert_kam
    UNION ALL BY NAME SELECT * FROM alert_marketing
),
kept AS (
    SELECT *,
           row_number() OVER (PARTITION BY team ORDER BY inr_at_risk_week DESC) AS rank_in_team
    FROM all_alerts
    WHERE inr_at_risk_week >= getvariable('min_inr_at_risk')
)
SELECT
    row_number() OVER (ORDER BY inr_at_risk_week DESC) AS priority,
    CAST(getvariable('as_of') AS DATE)                AS report_date,
    *
FROM kept
WHERE rank_in_team <= getvariable('max_alerts_per_team')
ORDER BY priority;
