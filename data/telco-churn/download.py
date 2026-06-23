"""Download IBM Telco Customer Churn dataset (public, no Kaggle account needed).

The same CSV is mirrored on GitHub by IBM Cognos Analytics samples.
"""
import io
import sys
from pathlib import Path

import pandas as pd
import requests

URL = (
    "https://raw.githubusercontent.com/IBM/telco-customer-churn-on-icp4d/"
    "master/data/Telco-Customer-Churn.csv"
)
OUT = Path(__file__).parent

def main() -> None:
    print(f"Downloading {URL} ...")
    r = requests.get(URL, timeout=30)
    r.raise_for_status()
    df = pd.read_csv(io.StringIO(r.text))
    print(f"Loaded {len(df)} rows, {len(df.columns)} cols")

    # 1) Full CSV → uri_file
    (OUT / "raw").mkdir(parents=True, exist_ok=True)
    df.to_csv(OUT / "raw" / "telco-churn.csv", index=False)

    # 2) Train/Test split → uri_folder
    (OUT / "folder").mkdir(parents=True, exist_ok=True)
    train = df.sample(frac=0.8, random_state=42)
    test = df.drop(train.index)
    train.to_csv(OUT / "folder" / "train.csv", index=False)
    test.to_csv(OUT / "folder" / "test.csv", index=False)

    # 3) MLTable copy
    (OUT / "mltable").mkdir(parents=True, exist_ok=True)
    df.to_csv(OUT / "mltable" / "telco-churn.csv", index=False)

    print(f"Saved to {OUT.resolve()}")

if __name__ == "__main__":
    sys.exit(main())
