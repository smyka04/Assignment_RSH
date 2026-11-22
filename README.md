# Joy quick-commerce weekly monitor

Flags supply, platform (KAM) and marketing problems from the weekly Blinkit / Zepto / Instamart exports,
biggest rupee impact first. Data work is in SQL (`sql/`), run by DuckDB.

## Run

```
pip install -r requirements.txt
python build.py                       # builds the report page: docs/index.html (open it in a browser)
python build.py --backtest            # prints the backtest: every Monday, 14 Sep to 16 Nov
python -m pytest -q                   # checks the 3 known problems are caught in week 1
```

Live page: https://smyka04.github.io/Assignment_RSH/

## Next week's data

Replace the CSVs in `data/` with the new export (same columns) and push. The GitHub Action in
`.github/workflows/build.yml` runs the tests, builds the report for the Monday after the newest
complete week in the data, and publishes it to GitHub Pages. Locally, `python build.py` does the same.

_Work in progress: the write-up is added in a later step._
