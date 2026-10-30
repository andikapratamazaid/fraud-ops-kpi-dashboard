# Building the same dashboard in Power BI

> The DAX below follows the standard patterns but was **not run in Power BI** while preparing this repo. Test each measure against the SQL views or the HTML dashboard and fix any small differences.

## 1. Load data
Import `data/scored_transactions.csv` (or connect to the PostgreSQL table `fraud_scored_transactions`). Name the table `T` below for brevity.

## 2. What-if parameter
Modeling > New parameter > Numeric range: name `Review Cost`, min 0, max 50, increment 0.5, default 5. Power BI creates the table `Review Cost` and the measure `Review Cost Value`.

## 3. Measures
```DAX
Transactions    = COUNTROWS ( T )
Alerts          = CALCULATE ( COUNTROWS ( T ), T[flagged] = 1 )
True Alerts     = CALCULATE ( COUNTROWS ( T ), T[flagged] = 1, T[is_fraud] = 1 )
Fraud Cases     = CALCULATE ( COUNTROWS ( T ), T[is_fraud] = 1 )

Alert Rate      = DIVIDE ( [Alerts], [Transactions] )
Precision       = DIVIDE ( [True Alerts], [Alerts] )
Recall          = DIVIDE ( [True Alerts], [Fraud Cases] )

Fraud Value     = CALCULATE ( SUM ( T[amount] ), T[is_fraud] = 1 )
Caught Value    = CALCULATE ( SUM ( T[amount] ), T[flagged] = 1, T[is_fraud] = 1 )
Missed Value    = [Fraud Value] - [Caught Value]

Net Savings     = [Caught Value] - [Review Cost Value] * [Alerts]

Cumulative Net Savings =
VAR h = MAX ( T[hour_index] )
RETURN CALCULATE ( [Net Savings], FILTER ( ALLSELECTED ( T[hour_index] ), T[hour_index] <= h ) )

Target Alert Rate =
CALCULATE ( [Alert Rate], REMOVEFILTERS ( T ), T[split] = "validation" )

Volume Spike = IF ( [Alert Rate] > 2 * [Target Alert Rate], 1, 0 )
```

## 4. Page layout (matches the HTML dashboard)
1. **Slicers:** `split` (default `test`), `Review Cost` parameter.
2. **Cards:** Transactions, Alerts, Precision, Recall, Caught Value, Net Savings.
3. **Stacked column chart:** X = `hour_index`, Y = `True Alerts` and `Alerts - True Alerts`.
4. **Line chart:** X = `hour_index`, Y = `Cumulative Net Savings`.
5. **Column chart:** X = `hour_index`, Y = `Alert Rate`, constant line = `Target Alert Rate`, conditional color by `Volume Spike`.
6. **Table:** amount band (add a calculated column with the same bands as `sql/02_kpi_views.sql`), Transactions, Alerts, Fraud Cases, Precision.

## 5. Threshold what-if
The exported `flagged` column is fixed at the model's threshold. To make the threshold interactive, create a second what-if parameter `Threshold` (0 to 1, small increment) and redefine `Alerts` as `CALCULATE ( COUNTROWS ( T ), T[score] >= [Threshold Value] )`, and do the same for `True Alerts` and `Caught Value`.
