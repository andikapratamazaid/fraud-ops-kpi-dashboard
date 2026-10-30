-- 02_kpi_views.sql  (PostgreSQL)
-- Operational KPI views for fraud monitoring. Filter on split = 'test' for the honest,
-- out-of-sample view (the threshold was tuned on the validation period).

-- Hourly KPIs ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_hourly_kpis AS
SELECT *,
       SUM(net_savings) OVER (PARTITION BY split ORDER BY hour_index) AS cumulative_net_savings
FROM (
    SELECT
        t.split,
        t.hour_index,
        COUNT(*)                                                                   AS transactions,
        SUM(t.flagged)                                                             AS alerts,
        SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)          AS true_alerts,
        SUM(t.is_fraud)                                                            AS fraud_cases,
        SUM(CASE WHEN t.is_fraud = 1 THEN t.amount ELSE 0 END)                     AS fraud_value,
        SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN t.amount ELSE 0 END)   AS caught_value,
        1.0 * SUM(t.flagged) / COUNT(*)                                            AS alert_rate,
        1.0 * SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)
            / NULLIF(SUM(t.flagged), 0)                                            AS alert_precision,
        1.0 * SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)
            / NULLIF(SUM(t.is_fraud), 0)                                           AS fraud_recall,
        SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN t.amount ELSE 0 END)
            - p.review_cost * SUM(t.flagged)                                       AS net_savings
    FROM fraud_scored_transactions t
    CROSS JOIN kpi_params p
    GROUP BY t.split, t.hour_index, p.review_cost
) h;

-- Daily roll-up (the dataset spans only ~2 days, so hourly is the useful grain) ----------
CREATE OR REPLACE VIEW v_daily_kpis AS
SELECT
    t.split,
    t.day,
    COUNT(*)                                                                   AS transactions,
    SUM(t.flagged)                                                             AS alerts,
    SUM(t.is_fraud)                                                            AS fraud_cases,
    SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN t.amount ELSE 0 END)   AS caught_value,
    1.0 * SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(t.flagged), 0)                                            AS alert_precision,
    SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN t.amount ELSE 0 END)
        - p.review_cost * SUM(t.flagged)                                       AS net_savings
FROM fraud_scored_transactions t
CROSS JOIN kpi_params p
GROUP BY t.split, t.day, p.review_cost;

-- Overall KPIs per split ------------------------------------------------------------------
CREATE OR REPLACE VIEW v_overall_kpis AS
SELECT
    t.split,
    COUNT(*)                                                                   AS transactions,
    SUM(t.flagged)                                                             AS alerts,
    SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)          AS true_alerts,
    SUM(t.is_fraud)                                                            AS fraud_cases,
    SUM(CASE WHEN t.is_fraud = 1 THEN t.amount ELSE 0 END)                     AS fraud_value,
    SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN t.amount ELSE 0 END)   AS caught_value,
    1.0 * SUM(t.flagged) / COUNT(*)                                            AS alert_rate,
    1.0 * SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(t.flagged), 0)                                            AS alert_precision,
    1.0 * SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(t.is_fraud), 0)                                           AS fraud_recall,
    SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN t.amount ELSE 0 END)
        - p.review_cost * SUM(t.flagged)                                       AS net_savings
FROM fraud_scored_transactions t
CROSS JOIN kpi_params p
GROUP BY t.split, p.review_cost;

-- By transaction amount band -----------------------------------------------------------------
CREATE OR REPLACE VIEW v_amount_band_kpis AS
SELECT
    t.split,
    CASE WHEN t.amount < 10   THEN '1) < 10'
         WHEN t.amount < 50   THEN '2) 10 - 50'
         WHEN t.amount < 200  THEN '3) 50 - 200'
         WHEN t.amount < 1000 THEN '4) 200 - 1,000'
         ELSE '5) 1,000+' END                                                  AS amount_band,
    COUNT(*)                                                                   AS transactions,
    SUM(t.flagged)                                                             AS alerts,
    SUM(t.is_fraud)                                                            AS fraud_cases,
    SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)          AS true_alerts,
    1.0 * SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(t.flagged), 0)                                            AS alert_precision,
    1.0 * SUM(CASE WHEN t.flagged = 1 AND t.is_fraud = 1 THEN t.amount ELSE 0 END)
        / NULLIF(SUM(CASE WHEN t.is_fraud = 1 THEN t.amount ELSE 0 END), 0)    AS value_caught_share
FROM fraud_scored_transactions t
GROUP BY t.split,
    CASE WHEN t.amount < 10   THEN '1) < 10'
         WHEN t.amount < 50   THEN '2) 10 - 50'
         WHEN t.amount < 200  THEN '3) 50 - 200'
         WHEN t.amount < 1000 THEN '4) 200 - 1,000'
         ELSE '5) 1,000+' END;

-- Volume monitoring: hours whose alert rate is more than 2x the validation-period target -----
CREATE OR REPLACE VIEW v_alert_volume_monitor AS
WITH target AS (
    SELECT 1.0 * SUM(flagged) / COUNT(*) AS target_rate
    FROM fraud_scored_transactions
    WHERE split = 'validation'
)
SELECT
    h.split,
    h.hour_index,
    h.transactions,
    h.alerts,
    h.alert_rate,
    tg.target_rate,
    h.alert_rate / tg.target_rate                                  AS times_target,
    CASE WHEN h.alert_rate > 2 * tg.target_rate THEN 1 ELSE 0 END  AS volume_spike
FROM v_hourly_kpis h
CROSS JOIN target tg;

-- Example queries ----------------------------------------------------------------------------
-- SELECT * FROM v_overall_kpis;
-- SELECT * FROM v_hourly_kpis WHERE split = 'test' ORDER BY hour_index;
-- SELECT * FROM v_alert_volume_monitor WHERE volume_spike = 1 ORDER BY hour_index;
