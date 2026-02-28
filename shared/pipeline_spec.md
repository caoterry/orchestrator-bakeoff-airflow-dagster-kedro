# Pipeline Spec: Bake-off (Airflow vs Dagster vs Kedro)

## Goal
Implement the SAME logical pipeline in three ways:
1) Airflow (orchestrator)
2) Dagster (orchestrator)
3) Kedro (pipeline framework; executed either standalone OR orchestrated)

## Input
- Source file: `data/input.csv`
- Schema (minimal):
  - ds (YYYY-MM-DD)
  - user_id (int)
  - amount (numeric)
  - category (string)

## Steps
1) Extract
   - Load rows for a given ds partition (e.g. 2026-02-27)
2) Transform
   - Validate schema
   - Remove duplicates by (ds, user_id, category)
   - Aggregate: sum(amount) by (ds, category)
   - **Failure injection**: first run for a given ds fails once (controlled by env var)
3) Load
   - Write results to Postgres table `poc.output_agg`
   - Must be idempotent per ds (delete then insert OR upsert)

## Operational Scenarios (must demo)
- Retry: transform fails once, then succeeds on retry
- Backfill: run for ds=2026-02-27 and ds=2026-02-28
- Observability: show where to see logs & run history in UI

## Comparison Rules
- All three produce identical `poc.output_agg` for the same ds
- Same Postgres used for business tables
- Keep business logic identical; differences should be orchestration/framework only
