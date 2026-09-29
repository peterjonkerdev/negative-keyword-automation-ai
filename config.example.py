"""Settings for the negative keyword pipeline.

Copy this file to config.py and fill it in during the setup interview (docs/setup-interview.md).
Commit config.py: the scheduled job reads it. Secrets never go here. API keys and tokens come from
environment variables: .env on your machine (gitignored), CI secret variables on the schedule.
"""

# BigQuery names. The SQL files use these placeholders; the loader replaces them from here.
BQ = {
    "project": "your-project",                    # the Google Cloud project
    "dataset": "your_dataset",                    # where the pipeline's tables live (sql/decisions.sql)
    "transfer_dataset": "your_transfer_dataset",  # where the Data Transfer lands
    "customer_id": "your_customer_id",            # the Google Ads customer ID, digits only
}

# The non-brand search campaigns the shared negative list is attached to. The query reads search
# terms from these campaigns only. IDs rather than names, so renaming a campaign changes nothing.
CAMPAIGN_IDS: list[int] = []

# Which search terms reach the model (docs/search-terms.md).
STATS_FILTER = {
    "lookback_days": 30,         # the stats window, ending yesterday
    "maturity_days": 7,          # the account's conversion lag: a term first clicked inside it waits
    "drop_if_converted": True,   # a converting term is never a negative candidate
    "min_cost": 5.0,             # spend in the window, in the account's currency; 0 turns the floor off
}

# The model call (docs/prompt.md, docs/pipeline.md).
MODEL = "your-model-id"          # a dated model version where the provider has one, not an alias:
                                 # an alias can move to a new model with no change in this repo
BATCH_SIZE = 100                 # terms per call; test 200 and 300 on the gold set before raising it
MAX_RETRIES = 3                  # rate limits and timeouts, retried with a growing wait

# The only phrases allowed as PHRASE negatives. The validator turns any other PHRASE into EXACT on
# the full search term. Must match the safe phrase list in prompts/business-context.md: a unit test
# compares the two.
SAFE_PHRASES: list[str] = ["marathon results", "clipart"]

# Gold set and gates (docs/gold-set.md, docs/evals.md).
GOLD_SET = {
    "path": "gold_set/example.csv",   # replace with your own set
    "daily_floor": 0.90,              # the daily check fails under this decision accuracy: a drift
                                      # alarm, not the bar a prompt change has to clear
    "runs_per_gate": 10,              # runs per prompt version, candidate and control, per gate
    "prod_tolerance_points": 2.0,     # the candidate's mean prod accuracy may sit at most this many
                                      # points under the control's
    "graduate_after": 10,             # a dev term joins the prod set after passing this many of
                                      # runs_per_gate runs: ten of ten
}

# The Slack summary (docs/pipeline.md). The token comes from the environment.
SLACK = {
    "channel": "#your-channel",
    "cadence": "weekly",              # daily, weekly or monthly
}
