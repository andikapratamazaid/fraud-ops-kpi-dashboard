-- 01_create_table.sql  (PostgreSQL)
-- Table fed by python/export_dashboard_data.py -> data/scored_transactions.csv

DROP TABLE IF EXISTS fraud_scored_transactions CASCADE;
DROP TABLE IF EXISTS kpi_params CASCADE;

CREATE TABLE fraud_scored_transactions (
    transaction_id BIGINT PRIMARY KEY,
    time_seconds   NUMERIC,            -- seconds since the first transaction in the dataset
    hour_index     INT,                -- floor(time_seconds / 3600)
    day            INT,                -- hour_index / 24 + 1
    split          TEXT,               -- 'validation' | 'test'
    score          DOUBLE PRECISION,   -- model fraud score
    amount         NUMERIC(12,2),
    is_fraud       SMALLINT,           -- ground-truth label (1 = fraud)
    flagged        SMALLINT            -- 1 if score >= chosen threshold
);

-- Business assumption used by the net-savings KPI (change to your real review cost)
CREATE TABLE kpi_params (review_cost NUMERIC);
INSERT INTO kpi_params VALUES (5.0);

-- \copy fraud_scored_transactions FROM 'data/scored_transactions.csv' CSV HEADER
