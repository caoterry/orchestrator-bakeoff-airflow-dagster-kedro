# Airflow Backfill vs Retry in This Repo

This PoC uses `airflow standalone` (`SequentialExecutor`) in `airflow/docker-compose.yml`.

## Why backfill can end `FAILED` with task `UP_FOR_RETRY`

`airflow dags backfill` is a CLI-driven historical runner. In standalone/`SequentialExecutor`, it can evaluate the DagRun terminal state before a delayed retry actually executes.

When a task fails with `retries=1` and `retry_delay=5s`, the task instance may be `UP_FOR_RETRY` (retry scheduled in the future). The backfill command can still close out the DagRun as `FAILED` for that backfill run, because no retry attempt has run yet in that backfill loop.  

By contrast, a normal scheduler/UI-triggered run is managed by the scheduler loop, so the retry is picked up after `retry_delay` and the DagRun can finish `SUCCESS`.

## Demo A: Backfill success (failure injection OFF)

Run from repo root:

```bash
# 1) network + services
docker network create poc-net >/dev/null 2>&1 || true
docker compose -f docker/docker-compose.yml up -d postgres
docker compose -f airflow/docker-compose.yml up -d airflow

# 2) unpause DAG
docker exec poc-airflow airflow dags unpause poc_bakeoff_shared_pipeline

# 3) prepare deterministic input for the two backfill days
docker exec -e PGPASSWORD=pocpass poc-postgres psql -U poc -d poc_db -v ON_ERROR_STOP=1 -c "
DELETE FROM poc.output_agg WHERE ds BETWEEN DATE '2026-02-27' AND DATE '2026-02-28';
DELETE FROM poc.raw_input WHERE ds BETWEEN DATE '2026-02-27' AND DATE '2026-02-28';
INSERT INTO poc.raw_input (ds, user_id, amount, category) VALUES
  ('2026-02-27', 1, 10, 'food'),
  ('2026-02-27', 2, 5, 'food'),
  ('2026-02-27', 3, 7, 'travel'),
  ('2026-02-28', 1, 4, 'food'),
  ('2026-02-28', 2, 6, 'travel'),
  ('2026-02-28', 3, 8, 'travel');
"

# 4) backfill with failure injection OFF
docker exec poc-airflow bash -lc "
unset POC_FAIL_ONCE
airflow dags backfill poc_bakeoff_shared_pipeline -s 2026-02-27 -e 2026-02-28
"

# 5) verify output in Postgres
docker exec -e PGPASSWORD=pocpass poc-postgres psql -U poc -d poc_db -c "
SELECT ds, category, total_amount
FROM poc.output_agg
WHERE ds BETWEEN DATE '2026-02-27' AND DATE '2026-02-28'
ORDER BY ds, category;
"
```

## Demo B: Retry success (failure injection ON)

Run from repo root:

```bash
# 1) restart Airflow with failure injection ON
POC_FAIL_ONCE=1 docker compose -f airflow/docker-compose.yml up -d --force-recreate airflow

# 2) make sure marker for chosen logical date is absent (example date)
docker exec poc-airflow rm -f /tmp/poc_fail_once_2026-03-01.marker

# 3) trigger one logical date (scheduler-managed run)
docker exec poc-airflow airflow dags trigger poc_bakeoff_shared_pipeline \
  --run-id retry-demo-2026-03-01 \
  --exec-date 2026-03-01T00:00:00+00:00

# 4) inspect state transitions; expect first try fail, then retry after ~5s, then success
docker exec poc-airflow airflow tasks states-for-dag-run \
  poc_bakeoff_shared_pipeline retry-demo-2026-03-01

# 5) verify output
docker exec -e PGPASSWORD=pocpass poc-postgres psql -U poc -d poc_db -c "
SELECT ds, category, total_amount
FROM poc.output_agg
WHERE ds = DATE '2026-03-01'
ORDER BY category;
"
```

## One-command helper

You can run `scripts/airflow_demo.sh` for Demo A plus printed instructions for Demo B.
