-- New search terms for the model: net-new terms from the non-brand campaigns that pass the stats filter.
-- See docs/search-terms.md.
--
-- Table names: the SQL loader replaces your-project, your_transfer_dataset, your_customer_id and
-- your_dataset from BQ in config.py.
-- Values: BigQuery query parameters, from STATS_FILTER and CAMPAIGN_IDS in config.py:
--   @lookback_days      INT64
--   @maturity_days      INT64
--   @drop_if_converted  BOOL
--   @min_cost           FLOAT64
--   @campaign_ids       ARRAY<INT64>
--
-- The window is the last @lookback_days days, ending yesterday: today's data has not landed yet.
-- CURRENT_DATE() is UTC. Pass the account's time zone if it differs, e.g. CURRENT_DATE('<time zone>').

WITH stats AS (
  SELECT
    search_term_view_search_term AS search_term,
    MIN(IF(metrics_clicks > 0, segments_date, NULL)) AS first_click,
    SUM(metrics_clicks) AS clicks,
    SUM(metrics_cost_micros) / 1000000 AS cost,
    SUM(metrics_conversions) AS conversions
  FROM `your-project.your_transfer_dataset.p_ads_SearchQueryStats_your_customer_id`
  WHERE
    -- The partition filter: BigQuery scans only the partitions in the window.
    _PARTITIONTIME >= TIMESTAMP(DATE_SUB(CURRENT_DATE(), INTERVAL @lookback_days DAY))
    AND _PARTITIONTIME < TIMESTAMP(CURRENT_DATE())
    -- The date filter: the stats window itself.
    AND segments_date >= DATE_SUB(CURRENT_DATE(), INTERVAL @lookback_days DAY)
    AND segments_date < CURRENT_DATE()
    -- The non-brand campaigns the shared negative list is attached to.
    AND campaign_id IN UNNEST(@campaign_ids)
  GROUP BY search_term
)

SELECT
  search_term,
  first_click,
  clicks,
  cost,
  conversions
FROM stats AS s
WHERE
  -- Net-new only: skip every term that already has a decision.
  NOT EXISTS (
    SELECT 1
    FROM `your-project.your_dataset.decisions` AS d
    WHERE d.search_term = s.search_term
  )
  -- Converted: a term with a conversion in the window is never sent.
  AND NOT (@drop_if_converted AND s.conversions > 0)
  -- Too new: a term first clicked inside the conversion lag waits, so it can still convert.
  -- A term with no clicks has no first_click and drops out here: it has cost nothing.
  AND s.first_click <= DATE_SUB(CURRENT_DATE(), INTERVAL @maturity_days DAY)
  -- Spend floor: 0 turns it off.
  AND s.cost >= @min_cost
-- Costliest first, so --limit N keeps the N terms that cost the most.
ORDER BY s.cost DESC
