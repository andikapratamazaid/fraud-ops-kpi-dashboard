#!/usr/bin/env python3
"""
Score the monitoring window with the trained fraud model and export:
  1. data/scored_transactions.csv  -> load into SQL / Power BI / Tableau
  2. dashboard/data.js             -> data for the standalone HTML dashboard

The feature engineering and the chronological 60/20/20 split are identical to the
modeling notebook (fraud-detection-card-transactions), so the monitoring window
(validation + test) contains only transactions the model never trained on.

Usage:
  python python/export_dashboard_data.py \
      --data data/creditcard.csv \
      --model models/fraud_model.joblib \
      --threshold models/threshold.json
"""
import argparse
import datetime as dt
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

V_COLS = [f"V{i}" for i in range(1, 29)]
FEATURES = V_COLS + ["log_amount", "hour"]
AMOUNT_EDGES = [10, 50, 200, 1000]
AMOUNT_LABELS = ["< 10", "10 - 50", "50 - 200", "200 - 1,000", "1,000+"]


def prepare(path):
    df = pd.read_csv(path).drop_duplicates().reset_index(drop=True)
    df = df.sort_values("Time").reset_index(drop=True)
    df["hour"] = (df["Time"] // 3600) % 24
    df["log_amount"] = np.log1p(df["Amount"])
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="data/creditcard.csv")
    ap.add_argument("--model", default="models/fraud_model.joblib")
    ap.add_argument("--threshold", default="models/threshold.json")
    ap.add_argument("--out-csv", default="data/scored_transactions.csv")
    ap.add_argument("--out-js", default="dashboard/data.js")
    ap.add_argument("--source-label", default="Credit Card Fraud Detection (ULB / Worldline)")
    ap.add_argument("--synthetic", action="store_true",
                    help="mark the export as synthetic demo data (shows a banner in the dashboard)")
    args = ap.parse_args()

    model = joblib.load(args.model)
    cfg = json.load(open(args.threshold))
    thr, review_cost = float(cfg["threshold"]), float(cfg["review_cost"])

    df = prepare(args.data)
    n = len(df)
    i_train, i_val = int(n * 0.6), int(n * 0.8)

    mon = df.iloc[i_train:].copy()
    mon["transaction_id"] = mon.index
    mon["split"] = np.where(mon.index < i_val, "validation", "test")
    mon["score"] = model.predict_proba(mon[FEATURES])[:, 1]
    mon["flagged"] = (mon["score"] >= thr).astype(int)
    mon["hour_index"] = (mon["Time"] // 3600).astype(int)
    mon["day"] = mon["hour_index"] // 24 + 1
    mon = mon.rename(columns={"Time": "time_seconds", "Amount": "amount", "Class": "is_fraud"})

    # ---- 1) CSV for SQL / BI tools -------------------------------------------------
    cols = ["transaction_id", "time_seconds", "hour_index", "day", "split",
            "score", "amount", "is_fraud", "flagged"]
    Path(args.out_csv).parent.mkdir(parents=True, exist_ok=True)
    mon[cols].to_csv(args.out_csv, index=False)

    # ---- 2) compact data for the HTML dashboard ------------------------------------
    h0, h1 = int(mon["hour_index"].min()), int(mon["hour_index"].max())
    nh = h1 - h0 + 1
    hrs = mon["hour_index"].to_numpy() - h0
    is_val = (mon["split"] == "validation").to_numpy()

    tx_val = np.bincount(hrs[is_val], minlength=nh)
    tx_test = np.bincount(hrs[~is_val], minlength=nh)

    band = np.digitize(mon["amount"].to_numpy(), AMOUNT_EDGES)
    nb = len(AMOUNT_LABELS)
    b_val = np.bincount(band[is_val], minlength=nb)
    b_test = np.bincount(band[~is_val], minlength=nb)

    # Keep every fraud + every transaction scoring at/above `floor`.
    # Everything else can never be flagged at a threshold >= floor, so it only needs to be counted.
    floor = min(thr, float(np.quantile(mon["score"], 0.95)))
    keep = ((mon["score"] >= floor) | (mon["is_fraud"] == 1)).to_numpy()
    k = mon[keep]
    rows = {
        "h": (k["hour_index"] - h0).astype(int).tolist(),
        "s": k["score"].round(8).tolist(),
        "a": k["amount"].round(2).tolist(),
        "f": k["is_fraud"].astype(int).tolist(),
        "p": (k["split"] == "test").astype(int).tolist(),   # 0 = validation, 1 = test
    }

    val = mon[mon["split"] == "validation"]
    meta = {
        "source": args.source_label,
        "synthetic": bool(args.synthetic),
        "generated": dt.date.today().isoformat(),
        "model": type(model).__name__ if not hasattr(model, "steps") else type(model.steps[-1][1]).__name__,
        "threshold": round(thr, 8),
        "review_cost": review_cost,
        "target_alert_rate": float((val["score"] >= thr).mean()),
        "floor": round(floor, 8),
        "n_transactions": int(len(mon)),
        "n_fraud": int(mon["is_fraud"].sum()),
        "bands": {"edges": AMOUNT_EDGES, "labels": AMOUNT_LABELS,
                  "tx_val": b_val.tolist(), "tx_test": b_test.tolist()},
    }
    payload = {"meta": meta,
               "hours": {"start": h0, "tx_val": tx_val.tolist(), "tx_test": tx_test.tolist()},
               "rows": rows}

    Path(args.out_js).parent.mkdir(parents=True, exist_ok=True)
    with open(args.out_js, "w") as f:
        f.write("window.FRAUD_DATA = " + json.dumps(payload, separators=(",", ":")) + ";\n")

    print(f"Monitoring window: {len(mon):,} transactions, hours {h0}-{h1}, {meta['n_fraud']} frauds")
    print(f"Wrote {args.out_csv}  ({len(mon):,} rows)")
    print(f"Wrote {args.out_js}  ({keep.sum():,} transaction rows kept, floor {floor:.6f})")


if __name__ == "__main__":
    main()
