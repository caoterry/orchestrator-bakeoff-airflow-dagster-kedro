import os
from pathlib import Path
import pandas as pd
from sqlalchemy import create_engine, text

def get_engine():
    url = os.environ.get("POC_DB_URL")
    if not url:
        raise RuntimeError("POC_DB_URL is not set (e.g. postgresql+psycopg2://poc:pocpass@localhost:5432/poc_db)")
    return create_engine(url, future=True)

def extract(ds: str) -> pd.DataFrame:
    engine = get_engine()
    with engine.connect() as conn:
        df = pd.read_sql(
            text("SELECT ds, user_id, amount, category FROM poc.raw_input WHERE ds = :ds"),
            conn,
            params={"ds": ds},
        )
    return df

def maybe_fail_once(ds: str):
    # Fail once per ds if enabled
    if os.environ.get("POC_FAIL_ONCE", "0") != "1":
        return
    marker_dir = Path(os.environ.get("POC_FAIL_MARKER_DIR", "/tmp"))
    marker_dir.mkdir(parents=True, exist_ok=True)
    marker = marker_dir / f"poc_fail_once_{ds}.marker"
    if not marker.exists():
        marker.write_text("failed once\n")
        raise RuntimeError(f"Injected failure for ds={ds} (first run only)")

def transform(df: pd.DataFrame, ds: str) -> pd.DataFrame:
    maybe_fail_once(ds)

    required = {"ds", "user_id", "amount", "category"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"Missing columns: {missing}")

    df2 = df.drop_duplicates(subset=["ds", "user_id", "category"]).copy()

    out = (
        df2.groupby(["ds", "category"], as_index=False)["amount"]
        .sum()
        .rename(columns={"amount": "total_amount"})
    )
    out["ds"] = pd.to_datetime(out["ds"]).dt.date
    return out

def load(out: pd.DataFrame, ds: str) -> None:
    engine = get_engine()
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM poc.output_agg WHERE ds = :ds"), {"ds": ds})
        out.to_sql("output_agg", conn, schema="poc", if_exists="append", index=False)

def run(ds: str) -> None:
    df = extract(ds)
    out = transform(df, ds)
    load(out, ds)
