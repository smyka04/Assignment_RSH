"""Turn the alert tables into what people read: team actions, WhatsApp messages and the web page.

No data logic lives here: every number comes from the SQL tables built by build.py.
"""
import json
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).parent
SITE_URL = "https://smyka04.github.io/Assignment_RSH/"


# --- formatting ---------------------------------------------------------------------------

def inr(x):
    """Rupees in Indian digit grouping: 1234567 -> ₹12,34,567."""
    if x is None:
        return "–"
    n = int(round(x))
    s = str(abs(n))
    if len(s) > 3:
        head, tail = s[:-3], s[-3:]
        groups = []
        while len(head) > 2:
            groups.insert(0, head[-2:])
            head = head[:-2]
        if head:
            groups.insert(0, head)
        s = ",".join(groups) + "," + tail
    return ("-" if n < 0 else "") + "₹" + s


def d(x: date, year=False):
    """6 Nov / 6 Nov 2026 (portable: %-d does not work on Windows)."""
    return f"{x.day} {x:%b}" + (f" {x.year}" if year else "")


def pct(x):
    return "–" if x is None else f"{round(x * 100)}%"


def short_name(product_name):
    return product_name.removeprefix("Joy ")


# --- one alert -> what to do --------------------------------------------------------------

def describe(a: dict, report_date: date) -> dict:
    """Add a one-line problem, the action, and the key figures for one alert."""
    p = short_name(a["product_name"])
    po_date = report_date - timedelta(days=7)
    where = f"{a['platform']} {a['city']}"
    avail = f"{round(a['availability_last_week'])}%" if a["availability_last_week"] is not None else "–"
    normal = f"{round(a['norm_availability'])}%"
    since = "new this week" if a["weeks_open"] == 1 else f"{a['weeks_open']} weeks, since {d(a['open_since'])}"

    if a["issue"] == "Short delivery":
        problem = f"Only {a['qty_delivered']} of {a['qty_ordered']} units of {p} delivered to {a['warehouse_id']} ({where})"
        action = (f"Send the {a['short_units']} missing units to {a['warehouse_id']} this week "
                  f"and fill the next PO in full.")
        detail = (f"{pct(a['fill_rate'])} fill rate on the {d(po_date)} PO. "
                  f"Dark-store availability last week {avail} (normal {normal}).")
    elif a["issue"] == "PO stopped":
        problem = f"{a['platform']} {a['city']} warehouse {a['warehouse_id']} has stopped ordering {p}"
        action = (f"Ask the {a['platform']} account manager why {a['warehouse_id']} has raised no PO "
                  f"since {d(a['open_since'])}, and get the order placed.")
        detail = (f"No PO for {a['weeks_open']} week{'s' if a['weeks_open'] > 1 else ''}. "
                  f"Usual order about {round(a['usual_qty_ordered'])} units a week. "
                  f"Dark-store availability last week {avail} (normal {normal}).")
    elif a["issue"] == "Stock-out, deliveries fine":
        problem = f"{p} is out of stock in {where} although our deliveries were complete"
        action = f"Ask {a['platform']} to check the listing and stock transfer to dark stores in {a['city']}."
        detail = f"Dark-store availability last week {avail} (normal {normal}). POs filled in full."
    elif a["issue"] == "Search rank drop":
        drop = 1 - a["units_per_store_day"] / a["base_units_per_store_day"]
        problem = (f"{p} fell from about #{round(a['usual_rank'])} to #{round(a['rank_last_week'])} "
                   f"in {a['platform']} search in {a['city']}")
        action = f"Run search ads / sponsored listing for {p} on {a['platform']} in {a['city']}."
        detail = (f"Stock is fine (availability {avail}), but sales per store are down {round(drop * 100)}% "
                  f"against weeks at the usual rank.")
    else:
        problem, action, detail = a["issue"], "", ""

    return {**a, "problem": problem, "action": action, "detail": detail, "since": since,
            "is_new": a["weeks_open"] == 1}


# --- WhatsApp messages --------------------------------------------------------------------

def whatsapp_messages(alerts: list[dict], report_date: date) -> list[dict]:
    """One message per recipient: supply team, each platform's KAM, marketing."""
    week = f"{d(report_date - timedelta(days=7))}–{d(report_date - timedelta(days=1))}"
    msgs = []

    def block(title, items, lines):
        body = [f"*{title}*", f"Week {week}", ""]
        for i, a in enumerate(items, 1):
            body += [f"{i}. {lines(a)}", ""]
        body.append(f"Full report: {SITE_URL}#{report_date.isoformat()}")
        return "\n".join(body)

    supply = [a for a in alerts if a["team"] == "Supply"]
    if supply:
        msgs.append({"to": "Supply team", "text": block(
            "Supply: short deliveries to fix", supply,
            lambda a: (f"*{a['warehouse_id']}* ({a['platform']} {a['city']}): {short_name(a['product_name'])}. "
                       f"Delivered {a['qty_delivered']} of {a['qty_ordered']} ({pct(a['fill_rate'])}). "
                       f"Please send the *{a['short_units']} missing units* this week."))})

    for platform in ["Blinkit", "Zepto", "Instamart"]:
        kam = [a for a in alerts if a["team"] == "KAM" and a["platform"] == platform]
        if kam:
            msgs.append({"to": f"{platform} account manager", "text": block(
                f"{platform}: please check these", kam,
                lambda a: (f"*{a['warehouse_id']}* ({a['city']}): {short_name(a['product_name'])}. "
                           + (f"No PO raised since {d(a['open_since'])}. Usual order is about "
                              f"{round(a['usual_qty_ordered'])} units a week and dark stores are at "
                              f"{round(a['availability_last_week'])}% availability. Can you get it ordered?"
                              if a["issue"] == "PO stopped" else
                              f"Dark stores at {round(a['availability_last_week'])}% availability although our "
                              f"deliveries were complete. Can you check the listing and stock transfer?")))})

    mkt = [a for a in alerts if a["team"] == "Marketing"]
    if mkt:
        msgs.append({"to": "Marketing", "text": block(
            "Marketing: products slipping in app search", mkt,
            lambda a: (f"*{short_name(a['product_name'])}* on {a['platform']} {a['city']}: search rank "
                       f"#{round(a['usual_rank'])} → #{round(a['rank_last_week'])} since {d(a['open_since'])}. "
                       f"Stock is fine. Costing about *{inr(a['inr_at_risk_week'])} a week*. "
                       f"Suggest search ads / sponsored listing."))})
    return msgs


# --- page data ----------------------------------------------------------------------------

def _rows(con, sql, params=None):
    cur = con.execute(sql, params or [])
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def site_data(con, known_problem_results) -> dict:
    """Everything the page shows, for every report Monday in the backtest."""
    mondays = [r["report_date"] for r in _rows(con, "SELECT report_date FROM backtest_runs ORDER BY 1")]
    reports = {}
    for m in mondays:
        alerts = [describe(a, m) for a in
                  _rows(con, "SELECT * FROM backtest_alerts WHERE report_date = ? ORDER BY priority", [m])]
        reports[m.isoformat()] = {
            "report_date": m,
            "week_from": m - timedelta(days=7),
            "week_to": m - timedelta(days=1),
            "total_inr": sum(a["inr_at_risk_week"] for a in alerts),
            "sales_last_week": con.execute(
                "SELECT coalesce(sum(sales_inr), 0) FROM sales WHERE week_start = ?",
                [m - timedelta(days=7)]).fetchone()[0],
            "alerts": alerts,
            "messages": whatsapp_messages(alerts, m),
        }

    known = [{
        "title": r["title"], "team": r["team"],
        "first_monday": r["first_monday"], "first_flagged": r["first_flagged"],
        "weeks_late": r["weeks_late"], "noticed_after": r["noticed_after"],
    } for r in known_problem_results]

    dq = _rows(con, "SELECT check_name, n_found, detail, what_we_did FROM dq_checks ORDER BY check_id")
    return {
        "generated": datetime.now().replace(microsecond=0),
        "latest": mondays[-1].isoformat(),
        "reports": reports,
        "known_problems": known,
        "data_checks": dq,
        "format": {"inr_example": inr(1234567)},
    }


def _json_default(o):
    if isinstance(o, (date, datetime)):
        return o.isoformat()
    raise TypeError(type(o))


def write_site(data: dict, out_dir: Path = ROOT / "docs"):
    """Write docs/index.html (data embedded, works offline) and docs/data/report.json."""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "data").mkdir(exist_ok=True)
    payload = json.dumps(data, default=_json_default, ensure_ascii=False, separators=(",", ":"))
    (out_dir / "data" / "report.json").write_text(
        json.dumps(data, default=_json_default, ensure_ascii=False, indent=1), encoding="utf-8")
    template = (ROOT / "templates" / "index.html").read_text(encoding="utf-8")
    html = template.replace("/*__DATA__*/null", payload.replace("</", "<\\/"))
    (out_dir / "index.html").write_text(html, encoding="utf-8")
    (out_dir / ".nojekyll").write_text("", encoding="utf-8")
    return out_dir / "index.html"
