"""Train and evaluate a 30-day readmission risk model on mart_readmissions.

Readmissions are rare, so evaluation uses 5-fold cross-validation grouped by
patient (no patient is in both train and test of a fold) and scores every stay
out of fold. Compares a logistic-regression baseline with gradient boosting and
writes every metric to results/readmission_model.json.
"""
import json
from pathlib import Path

import duckdb
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.model_selection import StratifiedGroupKFold
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
    cv = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)
    folds = list(cv.split(X, y, groups))

    def make_models():
        return {
            "logistic_regression": make_pipeline(
                StandardScaler(), LogisticRegression(max_iter=1000, class_weight="balanced")),
            "gradient_boosting": HistGradientBoostingClassifier(
                max_depth=3, learning_rate=0.05, max_iter=300, class_weight="balanced",
                random_state=42),
        }

    out = {
        "index_stays": int(len(df)),
        "patients": int(df["patient_id"].nunique()),
        "readmissions": int(y.sum()),
        "base_rate": round(float(y.mean()), 4),
        "evaluation": "StratifiedGroupKFold(5) by patient_id, seed 42, out-of-fold scores",
        "features": FEATURES,
        "models": {},
    }
    for name in make_models():
        oof = np.zeros(len(y))
        fold_auc = []
        for train, test in folds:
            model = make_models()[name].fit(X[train], y[train])
            oof[test] = model.predict_proba(X[test])[:, 1]
            if 0 < y[test].sum() < len(test):
                fold_auc.append(roc_auc_score(y[test], oof[test]))
        top = np.argsort(-oof)[: max(1, len(oof) // 10)]
        out["models"][name] = {
            "roc_auc_oof": round(float(roc_auc_score(y, oof)), 4),
            "pr_auc_oof": round(float(average_precision_score(y, oof)), 4),
            "roc_auc_fold_min": round(float(min(fold_auc)), 4),
            "roc_auc_fold_max": round(float(max(fold_auc)), 4),
            # share of all readmissions that fall in the top decile of predicted risk
            "top_decile_capture": round(float(y[top].sum() / y.sum()), 4),
        }
    # coefficients from a logistic model fit on all stays, for interpretation only
    models = {"logistic_regression": make_models()["logistic_regression"].fit(X, y)}
    lr = models["logistic_regression"][-1]
    out["logistic_coefficients"] = {
        f: round(float(c), 4) for f, c in sorted(zip(FEATURES, lr.coef_[0]), key=lambda t: -abs(t[1]))
    }
    (ROOT / "results").mkdir(exist_ok=True)
    (ROOT / "results" / "readmission_model.json").write_text(json.dumps(out, indent=2))
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
