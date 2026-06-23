#!/usr/bin/env bash
set -euo pipefail

ENV=${ENV:-dev}
RG="rg-churn-${ENV}"
WS="mlw-churn-${ENV}"
LAB_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "▶ 1/4  Download dataset (idempotent)"
uv run python "${LAB_DIR}/../../data/telco-churn/download.py"

echo "▶ 2/4  Register data assets (uri_file / uri_folder / mltable)"
for f in uri_file uri_folder mltable; do
  az ml data create -g "$RG" -w "$WS" -f "${LAB_DIR}/assets/${f}.yml" \
    || echo "  asset ${f} already exists at v1, skip"
done

echo "▶ 3/4  Submit three Command Jobs"
for f in train_uri_file train_uri_folder train_mltable; do
  az ml job create -g "$RG" -w "$WS" -f "${LAB_DIR}/jobs/${f}.yml" \
    --query name -o tsv
done

echo "▶ 4/4  Done. Track runs in Azure ML Studio → Jobs → lab02-data-and-job"
