from __future__ import annotations

from datetime import datetime, timedelta
from airflow.decorators import dag, task

@dag(
    dag_id="poc_bakeoff_shared_pipeline",
    start_date=datetime(2026, 2, 27),
    schedule="@daily",
    catchup=True,
    default_args={"retries": 1, "retry_delay": timedelta(seconds=5)},
    tags=["poc", "bakeoff"],
)
def poc_bakeoff_shared_pipeline():
    @task
    def run_for_ds(ds_str: str):
        # Fail once to demonstrate retry (set POC_FAIL_ONCE=1 in container env later)
        import poc_pipeline
        poc_pipeline.run(ds_str)

    run_for_ds("{{ ds }}")

poc_bakeoff_shared_pipeline()
