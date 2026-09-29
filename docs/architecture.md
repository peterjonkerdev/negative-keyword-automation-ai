# Architecture

## Parts

The system has seven parts. Each lives in one place and does one job.

| Part | Where it lives | What it does |
| --- | --- | --- |
| Search terms | BigQuery, filled daily by the Data Transfer | The account's search terms and their stats |
| Stats filter | `sql/new_search_terms.sql`, with `STATS_FILTER` in `config.py` | Drops the terms the numbers already settle, and the ones already judged |
| Gold set | `gold_set/`, a file of terms with known right answers | Scores every prompt change before it ships |
| Prompt | `prompts/negatives.md`, with `prompts/business-context.md` at the bottom | Reads each term and decides: `ADD_NEGATIVE`, `LEAVE` or `TO_REVIEW` |
| Pipeline | Python, run daily by CI | Calls the model in batches, validates the output, writes every decision to BigQuery, posts to Slack |
| Review | a Google Sheet to start | A person accepts or rejects each negative |
| Evals | the gold sets, and the rejections in BigQuery | Score the live prompt every day to track accuracy, and turn rejections into tested prompt fixes |

## Run-time flow

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Search terms │───▶│   Classify   │───▶│    Slack     │───▶│ Human review │───▶│ Apply in Ads │
│  (BigQuery)  │    │   + decide   │    │  (summary)   │    │(sheet or app)│    │  (by hand)   │
└──────────────┘    └──────▲───────┘    └──────────────┘    └──────┬───────┘    └──────────────┘
                           │                                       │
                           │  prompt improvements                  │ rejections
                           │                                       ▼
                           │                               ┌──────────────┐
                           └───────────────────────────────│  Eval loop   │
                                                           └──────────────┘
```

Each part has its own doc, in build order: `search-terms.md`, `gold-set.md`, `prompt.md`, `pipeline.md`, `review.md`, `evals.md`.

## Tables

All in `your-project.your_dataset`, defined in `sql/decisions.sql`.

| Table | One row per | Written by |
| --- | --- | --- |
| `decisions` | search term: the model's latest decision | the pipeline, through staging and a MERGE |
| `decisions_staging` | row the pipeline wrote, every run | the pipeline, append-only |
| `reviews` | reviewed decision: block or leave, and when it was applied | the review sync |
| `job_runs` | job run, with its counts | every job |

The decisions table is keyed on the search term alone, so it covers one account. More accounts need the account in the key.

## Code layout

A layout for the Python package the agent builds. The scheduled job runs `python -m negatives --live`.

```
negatives/
  __main__.py     entry point: flags, run ID, the six steps in order
  fetch.py        step 1: loads and runs sql/new_search_terms.sql
  request.py      step 2: fills the prompt, splits the terms into batches
  model.py        step 3: the provider client, retries, halving a cut-off batch
  validate.py     step 4: the Pydantic schema and the batch checks
  write.py        step 5: staging insert and MERGE
  notify.py       step 6: run log and Slack
  review.py       export to the review sheet, sync back, paste list
  evals.py        gold set scoring, the gates, the daily check
tests/
  fixtures/       frozen search terms and model replies for end-to-end runs
```
