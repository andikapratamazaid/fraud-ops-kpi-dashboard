# Data

Nothing here is committed (see `.gitignore`).

You need two inputs, both from the companion modeling project
[fraud-detection-card-transactions](https://github.com/andikapratamazaid/fraud-detection-card-transactions):

1. `data/creditcard.csv`: the Credit Card Fraud Detection dataset (ULB / Worldline, Kaggle `mlg-ulb/creditcardfraud`). Check the dataset page for its current license.
2. `models/fraud_model.joblib` and `models/threshold.json`: produced by that project's notebook (section 9, "Save the model").

Then run:

```bash
python python/export_dashboard_data.py
```

This writes `data/scored_transactions.csv` (for SQL / Power BI) and `dashboard/data.js` (for the HTML dashboard).
