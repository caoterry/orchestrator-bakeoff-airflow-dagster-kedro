#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIRFLOW_COMPOSE="$ROOT_DIR/airflow/docker-compose.yml"
POSTGRES_COMPOSE="$ROOT_DIR/docker/docker-compose.yml"
DAG_ID="poc_bakeoff_shared_pipeline"

echo "==> Ensuring Docker network exists (poc-net)"
docker network create poc-net >/dev/null 2>&1 || true

echo "==> Starting Postgres"
docker compose -f "$POSTGRES_COMPOSE" up -d postgres

echo "==> Starting Airflow (standalone)"
docker compose -f "$AIRFLOW_COMPOSE" up -d airflow

echo "==> Ensure containers share network even after --force-recreate"
docker network connect poc-net poc-postgres >/dev/null 2>&1 || true
docker network connect poc-net poc-airflow  >/dev/null 2>&1 || true

echo "==> Waiting for Airflow CLI to respond"
until docker exec poc-airflow airflow dags list >/dev/null 2>&1; do
  sleep 2
done

echo "==> Unpausing DAG: $DAG_ID"
docker exec poc-airflow airflow dags unpause "$DAG_ID"

echo "==> Preparing deterministic demo input for 2026-02-27..2026-02-28"
docker exec -e PGPASSWORD=pocpass poc-postgres psql -U poc -d poc_db -v ON_ERROR_STOP=1 -c "
TRUNCATE poc.output_agg;
TRUNCATE poc.raw_input;
INSERT INTO poc.raw_input (ds, user_id, amount, category) VALUES
  ('2026-02-27', 1, 10, 'food'),
  ('2026-02-27', 2, 5, 'food'),
  ('2026-02-27', 3, 7, 'travel'),
  ('2026-02-28', 1, 4, 'food'),
  ('2026-02-28', 2, 6, 'travel'),
  ('2026-02-28', 3, 8, 'travel');
"

echo "==> Backfill success path with failure injection OFF"
docker exec poc-airflow bash -lc "unset POC_FAIL_ONCE; airflow dags backfill $DAG_ID -s 2026-02-27 -e 2026-02-28"

echo "==> Verifying output in Postgres"
docker exec -e PGPASSWORD=pocpass poc-postgres psql -U poc -d poc_db -c "
SELECT ds, category, total_amount
FROM poc.output_agg
WHERE ds BETWEEN DATE '2026-02-27' AND DATE '2026-02-28'
ORDER BY ds, category;
"

cat <<'EOF'
==> Retry demo (manual steps)
1) Restart Airflow with failure injection enabled:
   POC_FAIL_ONCE=1 docker compose -f airflow/docker-compose.yml up -d --force-recreate airflow

2) (Optional) clear marker for the logical date you will trigger:
   docker exec poc-airflow rm -f /tmp/poc_fail_once_2026-03-01.marker

3) Trigger one logical date and watch task retry automatically after ~5s:
   docker exec poc-airflow airflow dags trigger poc_bakeoff_shared_pipeline \
     --run-id retry-demo-2026-03-01 \
     --exec-date 2026-03-01T00:00:00+00:00
   docker exec poc-airflow airflow tasks states-for-dag-run \
     poc_bakeoff_shared_pipeline retry-demo-2026-03-01

4) Verify output:
   docker exec -e PGPASSWORD=pocpass poc-postgres psql -U poc -d poc_db -c "
   SELECT ds, category, total_amount
   FROM poc.output_agg
   WHERE ds = DATE '2026-03-01'
   ORDER BY category;
   "
EOF
