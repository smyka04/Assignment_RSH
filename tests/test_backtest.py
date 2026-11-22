"""Checks that the monitor would have caught the three known problems in their first week,
without flooding anyone with alerts and without peeking at future data.

Run:  python -m pytest -q
"""
import csv
import sys
from datetime import date
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import build  # noqa: E402


@pytest.fixture(scope="module")
def bt():
    """One backtest over every Monday, shared by the tests below."""
    return build.backtest()


@pytest.fixture(scope="module")
def results(bt):
    return {r["id"]: r for r in build.known_problem_results(bt)}


# --- the three known problems -------------------------------------------------------------

@pytest.mark.parametrize("problem_id", [p["id"] for p in build.KNOWN_PROBLEMS])
def test_known_problem_flagged_in_first_week(results, problem_id):
    r = results[problem_id]
    assert r["first_flagged"] is not None, f"{r['title']}: never flagged"
    assert r["first_flagged"] == r["first_monday"], (
        f"{r['title']}: first flagged {r['first_flagged']}, should be {r['first_monday']}")


@pytest.mark.parametrize("problem_id", [p["id"] for p in build.KNOWN_PROBLEMS])
def test_every_affected_product_flagged_in_first_week(results, problem_id):
    assert results[problem_id]["all_skus_on_first"]


@pytest.mark.parametrize("problem_id", [p["id"] for p in build.KNOWN_PROBLEMS])
def test_known_problem_stays_flagged_until_fixed(results, problem_id):
    """Once flagged, a problem is repeated every Monday while it is still happening."""
    r = results[problem_id]
    expected = list(build.mondays(r["first_monday"], r["last_monday"]))
    assert r["mondays_flagged"] == expected


@pytest.mark.parametrize("problem_id", [p["id"] for p in build.KNOWN_PROBLEMS])
def test_known_problem_routed_to_right_team(bt, problem_id):
    p = next(x for x in build.KNOWN_PROBLEMS if x["id"] == problem_id)
    teams = bt.execute("""
        SELECT DISTINCT team FROM backtest_alerts
        WHERE platform = ? AND city = ? AND list_contains(?, sku_code) AND report_date = ?
    """, [p["platform"], p["city"], p["skus"], p["first_monday"]]).fetchall()
    assert teams == [(p["team"],)]


# --- noise --------------------------------------------------------------------------------

def test_no_monday_floods_the_teams(bt):
    worst = bt.execute("""
        SELECT max(n) FROM (SELECT report_date, count(*) AS n FROM backtest_alerts GROUP BY ALL)
    """).fetchone()[0]
    assert worst <= 10, f"one Monday produced {worst} alerts"
    per_team = bt.execute("""
        SELECT max(n) FROM (SELECT report_date, team, count(*) AS n FROM backtest_alerts GROUP BY ALL)
    """).fetchone()[0]
    assert per_team <= build.THRESHOLDS["max_alerts_per_team"]


def test_every_alert_is_worth_flagging(bt):
    smallest = bt.execute("SELECT min(inr_at_risk_week) FROM backtest_alerts").fetchone()[0]
    assert smallest >= build.THRESHOLDS["min_inr_at_risk"]


def test_16_nov_report(bt):
    """The live report: the four open problems on 16 Nov, biggest rupee impact first."""
    con = build.run(date(2026, 11, 16))
    got = con.execute("SELECT team, issue, warehouse_id, sku_code FROM alerts ORDER BY priority").fetchall()
    assert got == [
        ("KAM", "PO stopped", "ZEP-WH-08", "JY-LT-ALM-200"),
        ("Supply", "Short delivery", "BLK-WH-03", "JY-LT-ALM-400"),
        ("Marketing", "Search rank drop", "ZEP-WH-07", "JY-FW-NEEM-100"),
        ("Supply", "Short delivery", "BLK-WH-03", "JY-CR-NIGHT-50"),
    ]


# --- no peeking at the future -------------------------------------------------------------

def _truncate_data(src: Path, dst: Path, as_of: date):
    """Copy the CSVs keeping only rows a manager would have had on the morning of as_of."""
    dst.mkdir(parents=True, exist_ok=True)
    cutoffs = {"daily_sales.csv": "date", "purchase_orders.csv": "po_date"}
    for f in ["daily_sales.csv", "dark_stores.csv", "products.csv", "purchase_orders.csv"]:
        with open(src / f, newline="", encoding="utf-8") as fin, \
             open(dst / f, "w", newline="", encoding="utf-8") as fout:
            reader = csv.DictReader(fin)
            writer = csv.DictWriter(fout, fieldnames=reader.fieldnames)
            writer.writeheader()
            col = cutoffs.get(f)
            for row in reader:
                if col is None or row[col] < as_of.isoformat():
                    writer.writerow(row)


@pytest.mark.parametrize("as_of", [date(2026, 9, 21), date(2026, 9, 28), date(2026, 10, 19), date(2026, 11, 16)])
def test_no_future_data_leaks(tmp_path, as_of):
    """The report for a Monday is identical whether or not later data exists."""
    _truncate_data(ROOT / "data", tmp_path, as_of)
    q = "SELECT * EXCLUDE (priority) FROM alerts ORDER BY team, issue, warehouse_id, sku_code"
    full = build.run(as_of).execute(q).fetchall()
    cut = build.run(as_of, data_dir=tmp_path).execute(q).fetchall()
    assert full == cut


# --- input checks -------------------------------------------------------------------------

def test_cleaning_counts():
    con = build.load()
    assert con.execute("SELECT count(*) FROM raw_daily_sales").fetchone()[0] == 186_285
    assert con.execute("SELECT count(*) FROM sales").fetchone()[0] == 185_520     # 765 duplicates dropped
    assert con.execute("SELECT count(DISTINCT city) FROM dark_stores").fetchone()[0] == 6
    unmapped = con.execute("SELECT count(*) FROM sales WHERE sku_code IS NULL OR city IS NULL").fetchone()[0]
    assert unmapped == 0


def test_as_of_must_be_a_monday():
    with pytest.raises(ValueError):
        build.run(date(2026, 11, 15))
