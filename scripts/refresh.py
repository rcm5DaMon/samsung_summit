"""Import mode refresh: run ONE BigQuery query and write data/<page>.json for the four dashboard pages.

Runs in GitHub Actions (see .github/workflows/refresh.yml). Credentials come from
the GCP_SA_KEY secret via google-github-actions/auth, so nothing secret is in the repo.

Local run (optional):  pip install google-cloud-bigquery
                       gcloud auth application-default login
                       python scripts/refresh.py
"""
import json
import os
import pathlib
import sys

from google.cloud import bigquery

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = os.environ.get("BQ_PROJECT", "e-smart-433113")
MAX_GB = float(os.environ.get("MAX_GB", "1"))  # safety cap: refuse to run if the scan is bigger than this

sql = (ROOT / "sql" / "import.sql").read_text(encoding="utf-8")
client = bigquery.Client(project=PROJECT, location="asia-southeast2")

# 1) dry run = free cost check
dry = client.query(sql, job_config=bigquery.QueryJobConfig(dry_run=True, use_query_cache=False))
gb = dry.total_bytes_processed / 1e9
print(f"Dry run: query will scan {gb:.2f} GB")
if gb > MAX_GB:
    sys.exit(f"Aborting: scan {gb:.2f} GB is above MAX_GB={MAX_GB}. Check sql/import.sql.")

# 2) real run, capped so a bad edit can never bill more than MAX_GB
job = client.query(sql, job_config=bigquery.QueryJobConfig(
    maximum_bytes_billed=int(MAX_GB * 1e9),
    labels={"app": "samsung-summit-dashboard"},
))
row = next(iter(job.result()))
data = json.loads(row["j"])

if not data.get("targets"):
    sys.exit("Aborting: no target stores returned. Check the target tables and the period in sql/import.sql.")

t_all = sum(int(r.split("|")[6]) for r in data["targets"])
t_a = sum(int(r.split("|")[7]) for r in data["targets"])
mtd_all = sum(int(r.split("|")[2]) for r in data["daily"])
mtd_a = sum(int(r.split("|")[3]) for r in data["daily"])
print(f"Billed {job.total_bytes_billed / 1e9:.2f} GB · {len(data['targets'])} stores · "
      f"sales to {data['sales_asof']} · today {data['today_date'] or '-'} {data['today_last_time'] or ''}")
print(f"Summit Device: MTD {mtd_all:,} / target {t_all:,} · A Series: MTD {mtd_a:,} / target {t_a:,}")
pt = [r.split("|") for r in data["targets"]]
pdq = sum(int(r.split("|")[2]) for r in data.get("pdaily", []))
pdv = sum(int(r.split("|")[3]) for r in data.get("pdaily", []))
print(f"Pesta Akhir Tahun: qty 16 Nov-31 Dec {pdq:,} · value Rp {pdv:,} · "
      f"targets Nov {sum(int(r[17]) for r in pt):,} / Rp {sum(int(r[18]) for r in pt):,} · Dec {sum(int(r[19]) for r in pt):,} / Rp {sum(int(r[20]) for r in pt):,}")

# one data file per dashboard page (summit / aseries / racing / pesta): each page only carries its own numbers
sys.path.insert(0, str(ROOT / "scripts"))
from split_data import write_all  # noqa: E402
write_all(data, ROOT / "data")
