# Joy quick commerce weekly report

Every Monday, turns the Blinkit / Zepto / Instamart exports into one short report for the Quick Commerce Manager:
what went wrong last week, which team should act, how many rupees it is costing, and a WhatsApp message for each team.

- **Live report (Mon 16 Nov 2026):** https://smyka04.github.io/Assignment_RSH/
- **Monday's output as PDF and screenshots:** [`output/`](output/)
- **Note (what it flags, messy data, AI use):** [`NOTE.md`](NOTE.md)

## Run it

Python 3.12:

```
pip install -r requirements.txt
python build.py             
python build.py --backtest  
python -m pytest -q          
```

`python build.py --as-of 2026-10-19` builds the report as it would have looked on an earlier Monday.

## How it works

The data work is SQL, run by DuckDB from the CSVs in `data/`. `build.py` only runs the files in order.

| Step | File |
| --- | --- |
| Load the CSVs with explicit types | `sql/01_load.sql` |
| Clean: drop duplicates, fix city names, join products and stores | `sql/02_clean.sql` |
| Count every data problem found | `sql/03_data_quality.sql` |
| Weekly sales, purchase orders and baselines, using only data before the report Monday | `sql/04`–`06` |
| Alerts for supply, platform KAMs and marketing | `sql/10`–`12` |
| Rank by rupees at risk, drop small items, cap each team's list | `sql/20_rank_alerts.sql` |

`render.py` turns the alerts into actions and WhatsApp text, and fills `templates/index.html` to produce `docs/index.html`.

## Next week's data

Replace the CSVs in `data/` with the new export (same columns) and push. The GitHub Action
(`.github/workflows/build.yml`) runs the tests, builds the report for the Monday after the newest complete week,
and publishes it to GitHub Pages.
