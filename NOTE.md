# Note: Joy quick commerce weekly report

**16 Nov output:** 4 problems, about ₹52,000 of sales a week at risk. Live: https://smyka04.github.io/Assignment_RSH/ (PDF and screenshots in `output/`).

## What it flags and why

One flagging rule per team aimed at the cause of lost sales rather than the sales dip itself:

- **Supply:** last Monday's PO for a warehouse × product was under 70% delivered. Outside the known problems every PO was at least 74% filled; the problem POs were 45–59%.
- **Platform KAM:** a warehouse that normally orders a product raised no PO last Monday, flagged before the dark stores inventory runs dry.
- **Marketing:** search rank 3+ places worse than usual while stock is normal and sales per store are down.

Each item shows rupees at risk per week (reasons including units short, a normal week's order, or sales lost against usual, at the app price), biggest first, in the team's own terms, with a WhatsApp message to copy. Items under ₹1,000 are dropped and no team gets more than 10. The "sales dipped" rule fired about 200 times in 10 weeks, so it was left out.

**Backtest** (each Monday's report built only from data before that Monday):

| Problem | Visible from | Flagged on | Noticed in reality after |
| --- | --- | --- | --- |
| Blinkit Bengaluru, ~50% fill rate, six products | Mon 28 Sep | Mon 28 Sep | about 5 weeks |
| Zepto Bengaluru, face wash ~3rd → ~13th in search | Mon 19 Oct | Mon 19 Oct | about a month |
| Instamart Hyderabad, sunscreen POs stopped | Mon 21 Sep | Mon 21 Sep | about 3 weeks |

No Monday had more than 8 alerts. 21 tests check this, including that deleting later data leaves each report unchanged.
Backtest also showed that threshold/rule numbers worked here and could move a long way without changing results. This avoided the numbers being tuned to this specific dataset. 

## What was messy and what I did

- 765 exact duplicate sales rows: dropped.
- 11 spellings of 6 cities (Bangalore/Bengaluru, Delhi/New Delhi/Delhi NCR, HYDERABAD, "mumbai "): mapped to 6.
- 51 of 202 dark stores opened mid-period: compared sales per store-day so new stores don't look like growth.
- Product ids with leading zeros or letters (`IM062962`): read as text so they still match.
- 6 missing POs: kept as a signal by building a full warehouse × product × week grid.
- Assumptions: weeks run Monday–Sunday; "normal" availability is that week's median across all platforms, cities and products; rupee figures are rough. The PDF mentioned "our sunscreen", but both sunscreens stopped, so both are reported.

## How I used AI tools

- **Claude (Claude Code):** profiled the data, wrote the DuckDB SQL, Python, web page, tests, GitHub Action and README
- **What I decided:** execution plan, the output formatting, SQL for the data work, which SQL engine to use, the city merges, deduplication, the alert thresholds, the output page design, message content, README and NOTE
- **What I checked myself:** 16 Nov alerts against raw CSV files, backtest results, web page and messages, message content, output screenshots and PDF

## Potential future additions

- Pulling data automatically
- Optimise for mobile viewing
- Integrate Whatsapp message automation
- Competitor/category analysis
- Rupee estimation accuracy improvements (by season/growth, using ranges)
