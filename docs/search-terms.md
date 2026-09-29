# Search terms

The first query of every run reads the account's search terms from the Data Transfer, skips every term that already has a decision, and drops the terms the numbers already settle. The template is `sql/new_search_terms.sql`.

## Data Transfer

The [Google Ads Data Transfer](https://cloud.google.com/bigquery/docs/google-ads-transfer) lands the account's reports in a BigQuery dataset every day. The search terms report is the table `p_ads_SearchQueryStats_<customer_id>`: several rows per search term per day, split by campaign, ad group, matched keyword and other segments, with clicks, cost (`metrics_cost_micros`, divide by 1,000,000 for the account's currency) and conversions. The query adds them up per term. The view `ads_SearchQueryStats_<customer_id>` shows the same data; the query reads the partitioned table.

Two properties shape the query:

- The transfer loads each day after it has ended, so the last day or two can be missing when the job runs. The query's window ends yesterday.
- The transfer re-fetches only recent days (its refresh window). Conversions that arrive later never land in these tables. `docs/review.md` covers the check that catches them.

## Stats window

Read stats over a date range from the partitioned `p_ads_*` table, filtered twice on the same dates:

- on `segments_date`, the day the clicks happened, which defines the window
- on `_PARTITIONTIME`, the partition the transfer wrote, so the query scans only the days it needs

Both filters use values BigQuery knows before it scans: `CURRENT_DATE()` and query parameters. A filter that takes its dates from a subquery or a join scans the whole table. `CURRENT_DATE()` is UTC; pass the account's time zone if it differs.

Table names are placeholders (`your-project`, `your_transfer_dataset`, `your_customer_id`, `your_dataset`) that the SQL loader replaces from `BQ` in `config.py`. Filter values are BigQuery query parameters, never pasted into the SQL text.

The query reads only the campaigns in `CAMPAIGN_IDS`: the non-brand campaigns the shared negative list is attached to. IDs rather than names, so renaming a campaign changes nothing.

## Net-new terms

Every decision the model makes is stored in the `decisions` table. So the query skips every term that already has a decision (an anti-join: keep only the rows with no match in the other table) and sends only the net-new ones. The model bill then scales with the day's new terms rather than the size of the account.

The join key is the search term exactly as the transfer spells it. Normalise it the same way on both sides, or not at all.

A term the stats filter drops has no decision, so the query sees it again every run until it passes.

## Stats filter

- **Converted**: a term with a conversion in the lookback window is kept and never sent. Once its last conversion leaves the window, it becomes a candidate again.
- **Too new**: a term whose first click in the window falls inside the conversion lag waits, so it can still convert before anything judges it.
- **Spend floor**: a minimum spend in the window before a term is worth a model call. $5 is a sensible start.

The values live in `config.py`:

```python
# config.py: which search terms reach the model
STATS_FILTER = {
    "lookback_days": 30,
    "maturity_days": 7,          # the account's conversion lag
    "drop_if_converted": True,   # a converting term is never a negative candidate
    "min_cost": 5.0,             # 0 turns the floor off
}
```

The query returns the terms that pass, costliest first. `--limit N` keeps the first N.

## Tuning

- **Lookback**: a longer window catches slow terms and scans more. 30 days suits an account with steady daily volume; a low-volume account may want 60 or 90.
- **Maturity**: set it from the conversion lag, the number of days by which most conversions have arrived. The Days to conversion segment in Google Ads shows it.
- **Spend floor**: the floor decides how many rows reach a reviewer more than it decides the model bill. Raise it when the review sheet grows faster than the team works through it; lower it when the spend below the floor adds up.
- **Converted**: leave it on. A term that converts is not a negative candidate, whatever else it costs.

Change one value at a time and compare the counts before and after.

## First checks

Before the model sees any term:

1. Run the query read-only with the filters off (`min_cost` 0, `drop_if_converted` false, `maturity_days` 0), and compare total clicks and spend with the Google Ads search terms report for the same dates and campaigns. Completed days should match. The term count runs lower than the report's by design: a term with impressions and no clicks has cost nothing and drops out.
2. Turn the filters on one at a time and note how many terms and how much spend each one drops.
3. Zero rows usually means a wrong customer ID or dataset, campaign IDs that match nothing, or a transfer that has not loaded yet.
4. Costs should read in currency. Numbers a million times too large are micros.
