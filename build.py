"""Joy quick-commerce weekly monitor.

Runs the SQL pipeline in sql/ with DuckDB and writes the Monday report as a web page.
Usage:
    python build.py                        # build the web page (docs/index.html) for the latest Monday in data/
    python build.py --as-of 2026-10-19     # same, as if today were an earlier Monday
    python build.py --backtest             # print the backtest: every Monday, 14 Sep to 16 Nov 2026
"""
import argparse
from datetime import date, timedelta
from pathlib import Path

import duckdb

import render

ROOT = Path(__file__).parent

# Steps that do not depend on the report date: run once.
LOAD_FILES = ["01_load.sql", "02_clean.sql", "03_data_quality.sql"]
# Steps that are recomputed "as of" each report Monday, using only data before it.
REPORT_FILES = [
    "04_weekly_sales.sql", "05_weekly_po.sql", "06_baselines.sql",
    "10_alert_supply.sql", "11_alert_kam.sql", "12_alert_marketing.sql",
    "20_rank_alerts.sql",
]

# Alert thresholds (approved at review step 3.6).
THRESHOLDS = {
    "fill_rate_threshold": 0.70,   # PO fill rate below this = short delivery
    "rank_drop_places": 3,         # search rank this many places worse than usual
    "availability_gap_pts": 20,    # availability this many points below normal = stock-out
    "min_inr_at_risk": 1000,       # ignore alerts worth less than this per week (INR)
    "max_alerts_per_team": 10,     # never send a team more than this
}

# The three problems described in the assignment. "first_monday" is the first Monday on which
# the problem was visible in data before that date, read from the raw data:
#   1. Blinkit BLK-WH-01: the 21 Sep POs were ~50% filled (delivered by 25 Sep) -> Monday 28 Sep
#   2. Zepto Bengaluru Neem FW 100ml: rank went from ~3 to ~13 on Wed 14 Oct -> Monday 19 Oct
#   3. Instamart IM-WH-16: no sunscreen PO on Mon 14 Sep -> Monday 21 Sep
# "last_monday" is the last Monday the problem was still visible (it was fixed after that).
KNOWN_PROBLEMS = [
    {"id": 1, "title": "Blinkit Bengaluru: ~50% fill rate on six products",
     "team": "Supply", "issue": "Short delivery", "platform": "Blinkit", "city": "Bengaluru",
     "skus": ["JY-FW-NEEM-50", "JY-FW-NEEM-100", "JY-FW-PAP-100",
              "JY-LT-ALM-200", "JY-LT-ALM-400", "JY-LT-COCO-200"],
     "first_monday": date(2026, 9, 28), "last_monday": date(2026, 11, 2),
     "noticed_after": "about 5 weeks"},
    {"id": 2, "title": "Zepto Bengaluru: best-selling face wash fell from ~3rd to ~13th in search",
     "team": "Marketing", "issue": "Search rank drop", "platform": "Zepto", "city": "Bengaluru",
     "skus": ["JY-FW-NEEM-100"],
     "first_monday": date(2026, 10, 19), "last_monday": date(2026, 11, 16),
     "noticed_after": "about a month"},
    {"id": 3, "title": "Instamart Hyderabad: warehouse stopped ordering sunscreen for two weeks",
     "team": "KAM", "issue": "PO stopped", "platform": "Instamart", "city": "Hyderabad",
     "skus": ["JY-SS-SPF50-50", "JY-SS-MATTE-50"],
     "first_monday": date(2026, 9, 21), "last_monday": date(2026, 9, 28),
     "noticed_after": "about 3 weeks"},
]

FIRST_REPORT_MONDAY = date(2026, 9, 14)   # data starts Mon 7 Sep; the first full week ends Sun 13 Sep
LATEST_REPORT_MONDAY = date(2026, 11, 16)  # Monday after the last day in the supplied data


def load(data_dir: Path = ROOT / "data", thresholds: dict | None = None):
    """Load and clean the CSVs once. Returns an open DuckDB connection."""
    con = duckdb.connect()
    con.execute("SET VARIABLE data_dir = ?", [Path(data_dir).as_posix()])
    for name, value in {**THRESHOLDS, **(thresholds or {})}.items():
        con.execute(f"SET VARIABLE {name} = ?", [value])
    for f in LOAD_FILES:
        con.execute((ROOT / "sql" / f).read_text(encoding="utf-8"))
    return con


def report(con, as_of: date):
    """Build the report tables for one Monday on an already-loaded connection."""
    if as_of.weekday() != 0:
        raise ValueError(f"--as-of must be a Monday, got {as_of:%A %d %b %Y}")
    con.execute("SET VARIABLE as_of = ?::DATE", [as_of.isoformat()])
    for f in REPORT_FILES:
        con.execute((ROOT / "sql" / f).read_text(encoding="utf-8"))
    return con


def run(as_of: date, data_dir: Path = ROOT / "data", thresholds: dict | None = None):
    """Load, clean and build the report for one Monday."""
    return report(load(data_dir, thresholds), as_of)


def mondays(first: date = FIRST_REPORT_MONDAY, last: date = LATEST_REPORT_MONDAY):
    d = first
    while d <= last:
        yield d
        d += timedelta(days=7)


def latest_monday(con) -> date:
    """The Monday after the last complete Monday-Sunday week in the data.
    Data to Sun 15 Nov -> Mon 16 Nov. Data to Wed 18 Nov -> still Mon 16 Nov (that week is incomplete)."""
    return con.execute(
        "SELECT CAST(date_trunc('week', max(date) + INTERVAL 1 DAY) AS DATE) FROM sales").fetchone()[0]


def backtest(con=None, first: date = FIRST_REPORT_MONDAY, last: date | None = None):
    """Rerun the report for every Monday up to `last` (None = latest in the data).
    Stores every alert in table backtest_alerts."""
    con = con or load()
    last = last or latest_monday(con)
    con.execute("DROP TABLE IF EXISTS backtest_alerts")
    con.execute("CREATE OR REPLACE TABLE backtest_runs (report_date DATE)")
    for d in mondays(first, last):
        con.execute("INSERT INTO backtest_runs VALUES (?)", [d])
        report(con, d)
        if _has_table(con, "backtest_alerts"):
            con.execute("INSERT INTO backtest_alerts BY NAME SELECT * FROM alerts")
        else:
            con.execute("CREATE TABLE backtest_alerts AS SELECT * FROM alerts")
    return con


def known_problem_results(con):
    """For each known problem: first Monday the tool flagged it, versus when it became visible."""
    rows = []
    for p in KNOWN_PROBLEMS:
        hits = con.execute("""
            SELECT report_date, count(DISTINCT sku_code) AS n_skus, sum(inr_at_risk_week) AS inr
            FROM backtest_alerts
            WHERE team = ? AND issue = ? AND platform = ? AND city = ? AND list_contains(?, sku_code)
            GROUP BY report_date ORDER BY report_date
        """, [p["team"], p["issue"], p["platform"], p["city"], p["skus"]]).fetchall()
        flagged = [h[0] for h in hits]
        first = flagged[0] if flagged else None
        rows.append({
            **p,
            "first_flagged": first,
            "weeks_late": None if first is None else (first - p["first_monday"]).days // 7,
            "mondays_flagged": flagged,
            "all_skus_on_first": bool(hits) and hits[0][1] == len(p["skus"]),
            "inr_first_week": hits[0][2] if hits else None,
        })
    return rows


def _has_table(con, name):
    return con.execute("SELECT count(*) FROM duckdb_tables() WHERE table_name = ?", [name]).fetchone()[0] > 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--as-of", type=date.fromisoformat, default=None,
                    help="report Monday (YYYY-MM-DD); uses only data before this date. "
                         "Default: the Monday after the newest complete week in data/")
    ap.add_argument("--backtest", action="store_true",
                    help="rerun the report for every Monday from 14 Sep to 16 Nov 2026")
    args = ap.parse_args()

    if args.backtest:
        con = backtest(last=args.as_of)   # None = up to the latest Monday in the data
        print("Alerts per report Monday:")
        con.sql("""
            SELECT strftime(report_date, '%a %d %b') AS monday,
                   count(a.team) AS alerts,
                   count(*) FILTER (WHERE team = 'Supply')    AS supply,
                   count(*) FILTER (WHERE team = 'KAM')       AS kam,
                   count(*) FILTER (WHERE team = 'Marketing') AS marketing,
                   coalesce(round(sum(inr_at_risk_week)), 0) AS inr_at_risk_week
            FROM backtest_runs LEFT JOIN backtest_alerts a USING (report_date)
            GROUP BY report_date ORDER BY report_date
        """).show(max_width=200)
        print("Known problems: first Monday flagged")
        for r in known_problem_results(con):
            first = r["first_flagged"].strftime("%a %d %b") if r["first_flagged"] else "NOT FLAGGED"
            print(f"  {r['id']}. {r['title']}\n"
                  f"     visible from {r['first_monday']:%a %d %b}, flagged {first} "
                  f"({r['weeks_late']} weeks late), all products: {r['all_skus_on_first']}, "
                  f"actually noticed after {r['noticed_after']}")
        return

    # Default: build the web page for the report Monday, with every earlier Monday selectable.
    con = load()
    args.as_of = args.as_of or latest_monday(con)
    con = backtest(con, last=args.as_of)
    page = render.write_site(render.site_data(con, known_problem_results(con)))
    print(f"Report for {args.as_of:%a %d %b %Y}:")
    con.sql("""
        SELECT priority, team, issue, platform, city, warehouse_id, sku_code,
               strftime(open_since, '%d %b') AS open_since, weeks_open,
               round(inr_at_risk_week) AS inr_at_risk_week
        FROM backtest_alerts WHERE report_date = ? ORDER BY priority
    """, params=[args.as_of]).show(max_width=200)
    print(f"Web page written to {page.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
