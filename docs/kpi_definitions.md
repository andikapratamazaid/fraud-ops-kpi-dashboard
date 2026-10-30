# KPI Definitions

Unit of analysis: one scored transaction. A transaction is an **alert** when its model score is at or above the chosen threshold.

| KPI | Definition | Why an operations team cares |
|---|---|---|
| Transactions | Count of scored transactions in the window | Volume baseline |
| Alerts | Transactions with `score >= threshold` | Analyst workload |
| Alert rate | Alerts / transactions | Capacity planning, drift signal |
| Precision | True-fraud alerts / alerts | Share of analyst effort that hits real fraud |
| Recall (cases) | True-fraud alerts / all fraud cases | Share of fraud cases caught |
| Fraud value | Sum of `amount` over fraud cases | Total exposure |
| Fraud value caught | Sum of `amount` over true-fraud alerts | Loss prevented (if alert = block) |
| Fraud value missed | Fraud value - value caught | Loss that got through |
| Review cost | Assumed cost of one manual review (parameter) | Cost side of the trade-off |
| Net savings | Value caught - review cost x alerts | The single number the threshold is tuned on |
| Cumulative net savings | Running sum of hourly net savings | Shows whether the program keeps paying for itself |
| Volume spike | Hour whose alert rate is above 2x the target | Early warning of an attack burst or model drift |

## Target alert rate
The share of validation-period transactions flagged at the chosen threshold. It is the "normal" volume the team staffed for. An hour above 2x that level is flagged amber.

## Assumptions and limits
- A flagged fraud is assumed to be fully prevented. Real blocking is imperfect, so net savings is an upper bound.
- No customer-friction cost is attached to false alarms.
- The review cost is an assumption, not a measured value; the dashboard lets you change it.
- The dataset has no calendar dates, so the time axis is "hours since the first transaction". It also spans only about two days, so day-level trends are not meaningful.
- The threshold was tuned on the validation period, so validation KPIs are optimistic. Use the test period for the honest view.
- In production, fraud labels arrive late (chargebacks), so precision and recall of recent hours are provisional.
