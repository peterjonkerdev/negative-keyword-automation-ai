-- The tables the pipeline writes, in your-project.your_dataset. Run once at setup.
-- The SQL loader replaces your-project and your_dataset from BQ in config.py.
--
--   decisions          one row per search term: the model's latest decision
--   decisions_staging  every row the pipeline writes lands here first; a MERGE moves it into decisions
--   reviews            what a person decided about each decision, kept apart so a reprocessed
--                      term keeps its review history
--   job_runs           one row per job run
--
-- Monthly partitions: these tables grow by one day's new terms at a time, too little to fill
-- daily partitions. Clustering on search_term serves the anti-join and the MERGE.

CREATE TABLE IF NOT EXISTS `your-project.your_dataset.decisions` (
  search_term      STRING NOT NULL,     -- the key: the term exactly as the Data Transfer spells it
  decision         STRING NOT NULL,     -- ADD_NEGATIVE, LEAVE or TO_REVIEW
  negative         STRING,              -- the negative keyword text, ADD_NEGATIVE only
  match_type       STRING,              -- EXACT or PHRASE, ADD_NEGATIVE only
  intent           STRING,              -- transactional, commercial, informational, navigational; NULL if unknown
  category         STRING,              -- a category from the business context, or none; NULL if unknown
  brand            BOOL,                -- NULL for an unknown term
  competitor       BOOL,                -- NULL for an unknown term
  reason           STRING,              -- the model's one line; "unknown term" from step 0
  run_id           STRING NOT NULL,     -- the run that wrote this decision
  prompt_version   STRING NOT NULL,     -- short hash of prompts/negatives.md as sent
  context_version  STRING NOT NULL,     -- short hash of prompts/business-context.md as sent
  model_version    STRING NOT NULL,     -- the exact model ID, never an alias
  created_at       TIMESTAMP NOT NULL,  -- first decision for this term
  updated_at       TIMESTAMP NOT NULL   -- latest change, e.g. after reprocessing
)
PARTITION BY TIMESTAMP_TRUNC(created_at, MONTH)
CLUSTER BY decision, search_term
OPTIONS (description = "One row per search term: the model's latest decision.");

-- Append-only: the record of every row every run wrote. The MERGE reads one run's rows at a time
-- and keeps the newest row per search term (docs/pipeline.md).
CREATE TABLE IF NOT EXISTS `your-project.your_dataset.decisions_staging` (
  search_term      STRING NOT NULL,
  decision         STRING NOT NULL,
  negative         STRING,
  match_type       STRING,
  intent           STRING,
  category         STRING,
  brand            BOOL,
  competitor       BOOL,
  reason           STRING,
  run_id           STRING NOT NULL,
  prompt_version   STRING NOT NULL,
  context_version  STRING NOT NULL,
  model_version    STRING NOT NULL,
  staged_at        TIMESTAMP NOT NULL
)
PARTITION BY TIMESTAMP_TRUNC(staged_at, MONTH)
CLUSTER BY run_id, search_term;

-- One row per reviewed decision, written by the review sync (docs/review.md).
-- Accept and block are stored as BLOCK, reject and leave as LEAVE.
CREATE TABLE IF NOT EXISTS `your-project.your_dataset.reviews` (
  search_term       STRING NOT NULL,
  run_id            STRING NOT NULL,    -- the run whose decision was reviewed; key with search_term
  decision          STRING NOT NULL,    -- what the model decided: ADD_NEGATIVE or TO_REVIEW
  outcome           STRING NOT NULL,    -- what the person decided: BLOCK or LEAVE
  negative          STRING,             -- the negative text as approved (a reviewer may edit it)
  match_type        STRING,             -- the match type as approved
  rejection_reason  STRING,             -- one of the preset reasons
  comment           STRING,             -- the reviewer's free text
  reviewer          STRING,
  reviewed_at       TIMESTAMP NOT NULL,
  applied_at        TIMESTAMP,          -- when the negative went into the account
  failure_mode      STRING              -- set by triage for a rejection (docs/evals.md)
)
PARTITION BY TIMESTAMP_TRUNC(reviewed_at, MONTH)
CLUSTER BY outcome, search_term;

-- One row per job run: the daily run, the review sync and the accuracy check.
CREATE TABLE IF NOT EXISTS `your-project.your_dataset.job_runs` (
  run_id           STRING NOT NULL,
  job              STRING NOT NULL,     -- negatives-daily, review-sync or accuracy-check
  live             BOOL NOT NULL,       -- FALSE for a dry run
  status           STRING NOT NULL,     -- running, success or failed
  started_at       TIMESTAMP NOT NULL,
  finished_at      TIMESTAMP,
  terms_fetched    INT64,               -- rows the search terms query returned
  n_add_negative   INT64,               -- decisions written, by decision
  n_leave          INT64,
  n_to_review      INT64,
  invalid_rows     INT64,               -- rows validation dropped; their terms stay unjudged
  failed_batches   INT64,               -- batches that failed after every retry
  accuracy         FLOAT64,             -- accuracy-check only: decision accuracy on the prod gold set
  prompt_version   STRING,
  context_version  STRING,
  model_version    STRING,
  error            STRING
)
PARTITION BY TIMESTAMP_TRUNC(started_at, MONTH)
CLUSTER BY job;
