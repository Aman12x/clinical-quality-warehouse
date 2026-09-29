"""Train and evaluate a 30-day readmission risk model on mart_readmissions.

Splits by patient (no patient appears in both train and test), compares a
logistic-regression baseline with gradient boosting, and writes every metric
to results/readmission_model.json.
"""
import json
from pathlib import Path

import duckdb
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

ROOT = Path(__file__).resolve().parents[1]
FEATURES = [
    "age_at_admit", "is_female", "length_of_stay_days", "prior_inpatient_365d",
    "ed_visits_180d", "active_medications_at_admit", "has_diabetes", "has_hypertension",
    "has_heart_failure", "has_coronary_heart_disease", "has_chronic_kidney_disease", "has_copd",
]


def load():
    con = duckdb.connect(str(ROOT / "warehouse.duckdb"), read_only=True)
    df = con.execute(
        "select *, (gender = 'F')::int as is_female from marts.mart_readmissions"
    ).df()
    con.close()
    X = df[FEATURES].astype(float).to_numpy()
    y = df["readmitted_30d"].astype(int).to_numpy()
    return df, X, y, df["patient_id"].to_numpy()


def main() -> None:
    df, X, y, groups = load()
    split = GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=42)
    train, test = next(split.split(X, y, groups))

    models = {
        "logistic_regression": make_pipeline(
            StandardScaler(), LogisticRegression(max_iter=1000, class_weight="balanced")),
        "gradient_boosting": HistGradientBoostingClassifier(
            max_depth=3, learning_rate=0.05, max_iter=300, class_weight="balanced", random_state=42),
    }
    out = {
        "index_stays": int(len(df)),
        "patients": int(df["patient_id"].nunique()),
        "readmissions": int(y.sum()),
        "base_rate": round(float(y.mean()), 4),
        "train_stays": int(len(train)), "test_stays": int(len(test)),
        "test_readmissions": int(y[test].sum()),
        "split": "GroupShuffleSplit by patient_id, test_size=0.25, seed 42",
        "features": FEATURES,
        "models": {},
    }
    for name, model in models.items():
        model.fit(X[train], y[train])
        p = model.predict_proba(X[test])[:, 1]
        # share of test readmissions caught in the top decile of predicted risk
        top = np.argsort(-p)[: max(1, len(p) // 10)]
        out["models"][name] = {
            "roc_auc": round(float(roc_auc_score(y[test], p)), 4),
            "pr_auc": round(float(average_precision_score(y[test], p)), 4),
            "top_decile_capture": round(float(y[test][top].sum() / max(1, y[test].sum())), 4),
        }
    lr = models["logistic_regression"][-1]
    out["logistic_coefficients"] = {
        f: round(float(c), 4) for f, c in sorted(zip(FEATURES, lr.coef_[0]), key=lambda t: -abs(t[1]))
    }
    (ROOT / "results").mkdir(exist_ok=True)
    (ROOT / "results" / "readmission_model.json").write_text(json.dumps(out, indent=2))
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
