#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <ds YYYY-MM-DD>"
  exit 1
fi

DS="$1"
export POC_DB_URL="${POC_DB_URL:-postgresql+psycopg2://poc:pocpass@localhost:5432/poc_db}"

PYTHONPATH="$(pwd)/shared/python" python -c "from poc_pipeline import run; run('${DS}')"
