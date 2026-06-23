"""Lab 02 training script.

Reads the Telco churn data from one of three Azure ML data asset types
(uri_file / uri_folder / mltable), trains a logistic-regression churn
classifier, and logs metrics + model to MLflow.
"""
import argparse
import os

import mlflow
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

TARGET = "Churn"
DROP_COLS = ["customerID"]


def _coerce(df: pd.DataFrame) -> pd.DataFrame:
    """Telco raw has blank TotalCharges strings; coerce to numeric and drop NaNs."""
    if "TotalCharges" in df.columns:
        df["TotalCharges"] = pd.to_numeric(df["TotalCharges"], errors="coerce")
    df = df.drop(columns=[c for c in DROP_COLS if c in df.columns])
    df = df.dropna()
    return df


def load_data(training_data: str, asset_type: str):
    """Return (train_df, test_df) depending on the asset type."""
    if asset_type == "uri_file":
        df = _coerce(pd.read_csv(training_data))
        return train_test_split(df, test_size=0.2, random_state=42)

    if asset_type == "uri_folder":
        train = _coerce(pd.read_csv(os.path.join(training_data, "train.csv")))
        test = _coerce(pd.read_csv(os.path.join(training_data, "test.csv")))
        return train, test

    if asset_type == "mltable":
        import mltable

        tbl = mltable.load(training_data)
        df = _coerce(tbl.to_pandas_dataframe())
        return train_test_split(df, test_size=0.2, random_state=42)

    raise ValueError(f"Unknown asset_type: {asset_type}")


def build_pipeline(df: pd.DataFrame, max_iter: int, c: float) -> Pipeline:
    features = [col for col in df.columns if col != TARGET]
    numeric = df[features].select_dtypes(include="number").columns.tolist()
    categorical = [col for col in features if col not in numeric]

    pre = ColumnTransformer(
        transformers=[
            ("num", StandardScaler(), numeric),
            ("cat", OneHotEncoder(handle_unknown="ignore"), categorical),
        ]
    )
    return Pipeline(
        steps=[
            ("pre", pre),
            ("clf", LogisticRegression(max_iter=max_iter, C=c)),
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--training_data", type=str, required=True)
    parser.add_argument("--asset_type", type=str, required=True)
    parser.add_argument("--max_iter", type=int, default=200)
    parser.add_argument("--c", type=float, default=1.0)
    args = parser.parse_args()

    mlflow.sklearn.autolog()

    train_df, test_df = load_data(args.training_data, args.asset_type)
    y_train = (train_df[TARGET] == "Yes").astype(int)
    y_test = (test_df[TARGET] == "Yes").astype(int)
    x_train = train_df.drop(columns=[TARGET])
    x_test = test_df.drop(columns=[TARGET])

    with mlflow.start_run():
        mlflow.log_params({"asset_type": args.asset_type, "max_iter": args.max_iter, "c": args.c})
        model = build_pipeline(train_df, args.max_iter, args.c)
        model.fit(x_train, y_train)

        preds = model.predict(x_test)
        proba = model.predict_proba(x_test)[:, 1]
        acc = accuracy_score(y_test, preds)
        auc = roc_auc_score(y_test, proba)
        mlflow.log_metrics({"accuracy": acc, "roc_auc": auc})
        print(f"asset_type={args.asset_type} accuracy={acc:.4f} roc_auc={auc:.4f}")


if __name__ == "__main__":
    main()
