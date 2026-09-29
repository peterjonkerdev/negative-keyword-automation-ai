# Pipeline

The pipeline is one Python entry point that runs the steps in order, each small and testable on its own.

```bash
uv run python -m negatives              # dry run: calls the model, writes nothing
uv run python -m negatives --limit 20   # dry run on the 20 costliest terms
uv run python -m negatives --live       # the scheduled run
```

## Steps

1. **Fetch**: run `sql/new_search_terms.sql` with the values in `STATS_FILTER` and `CAMPAIGN_IDS` (`docs/search-terms.md`).
2. **Build the request**: fill the prompt with its business context (`docs/prompt.md`) and split the terms into batches of `BATCH_SIZE`. The filled prompt goes first in every call; the batch follows as a JSON array.
3. **Call the model**: ask for JSON, and use the provider's structured output mode where it has one, with the schema below. A reply cut off before the last term is retried with the batch halved.
4. **Validate**: every object against the [Pydantic](https://docs.pydantic.dev/) schema, and every returned term against the batch: every term was in the batch, and each comes back exactly once. An invalid row is logged and dropped; its term stays unjudged, so the next run picks it up.
5. **Write**: after each batch, insert the rows into `decisions_staging`, then MERGE them into `decisions`, keyed on the search term, with the run ID on every row.
6. **Notify**: write the run's counts to `job_runs`, and post to Slack when a summary is due.

## Output schema

```python
from typing import Literal

from pydantic import BaseModel, ValidationError, model_validator

Intent = Literal["transactional", "commercial", "informational", "navigational"]
Category = Literal["shoes", "apparel", "accessories", "none"]  # your categories, as in step 1 of the prompt


class TermDecision(BaseModel):
    search_term: str
    intent: Intent | None            # None only for an unknown term (step 0)
    category: Category | None
    brand: bool | None
    competitor: bool | None
    decision: Literal["ADD_NEGATIVE", "LEAVE", "TO_REVIEW"]
    negative: str | None             # ADD_NEGATIVE only
    match_type: Literal["EXACT", "PHRASE"] | None
    reason: str

    @model_validator(mode="after")
    def fields_match_decision(self) -> "TermDecision":
        blocks = self.decision == "ADD_NEGATIVE"
        if blocks and not (self.negative and self.match_type):
            raise ValueError("ADD_NEGATIVE needs a negative and a match type")
        if not blocks and (self.negative or self.match_type):
            raise ValueError("only ADD_NEGATIVE carries a negative")
        if self.reason == "unknown term" and self.decision != "TO_REVIEW":
            raise ValueError("an unknown term is TO_REVIEW")
        return self


class Reply(BaseModel):
    decisions: list[TermDecision]
```

Pass `Reply`'s JSON schema to the provider's structured output mode, adjusted to the schema features that provider supports. The reply is an object with one key, `decisions`, because some providers accept only an object at the root of a schema.

The provider's schema check covers types and allowed values, not the cross-field rules in the validator, so validate each object on its own: one bad row drops only itself.

```python
def parse(reply_text: str) -> list[TermDecision]:
    try:
        objects = json.loads(reply_text)["decisions"]
    except (json.JSONDecodeError, KeyError) as error:
        raise ReplyCutOff from error  # unreadable JSON is handled like a cut-off reply
    rows = []
    for obj in objects:
        try:
            rows.append(TermDecision.model_validate(obj))
        except ValidationError as error:
            log.warning("invalid row dropped: %s", error)
    return rows
```

## Cut-off replies

```python
def judge(batch: list[str]) -> list[TermDecision]:
    """Call the model. A reply cut off before the last term is retried with the batch halved."""
    try:
        return parse(call_model(batch))
    except ReplyCutOff:  # the provider's max-tokens stop reason, or JSON that ends early
        if len(batch) == 1:
            log.error("cut off on a single term, left unjudged: %r", batch[0])
            return []
        middle = len(batch) // 2
        return judge(batch[:middle]) + judge(batch[middle:])
```

## Batch checks

```python
from collections import Counter

from config import SAFE_PHRASES


def check_batch(batch: list[str], rows: list[TermDecision]) -> list[TermDecision]:
    """Keep the rows whose term was in the batch and came back exactly once."""
    sent = set(batch)
    counts = Counter(row.search_term for row in rows)
    kept = []
    for row in rows:
        if row.search_term not in sent:
            log.warning("not in the batch, dropped: %r", row.search_term)
        elif counts[row.search_term] > 1:
            log.warning("returned more than once, dropped: %r", row.search_term)
        else:
            kept.append(exact_by_default(row))
    return kept  # a term with no kept row stays unjudged, and the next run picks it up


def exact_by_default(row: TermDecision) -> TermDecision:
    """EXACT on the full term, unless the phrase is on the safe list."""
    if row.decision != "ADD_NEGATIVE":
        return row
    if row.match_type == "PHRASE" and row.negative in SAFE_PHRASES and row.negative in row.search_term:
        return row
    if (row.negative, row.match_type) != (row.search_term, "EXACT"):
        log.info("exact default applied: %r", row.search_term)
    return row.model_copy(update={"negative": row.search_term, "match_type": "EXACT"})
```

The second function is where "exact by default" lives in code. An exact negative whose text differs from the search term does not block that search at all, so an `EXACT` row always carries the full term.

## Staging and MERGE

Each batch is inserted into `decisions_staging` and merged right away, so a run that crashes halfway keeps every batch it wrote. The staging rows are deduplicated inside the MERGE: a MERGE does not deduplicate its own source, so two staged rows for a new term would insert twice, and two for an existing term would fail the statement.

```sql
MERGE `your-project.your_dataset.decisions` AS d
USING (
  SELECT *
  FROM `your-project.your_dataset.decisions_staging`
  WHERE run_id = @run_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY search_term ORDER BY staged_at DESC) = 1
) AS s
ON d.search_term = s.search_term
WHEN MATCHED THEN UPDATE SET
  decision = s.decision, negative = s.negative, match_type = s.match_type,
  intent = s.intent, category = s.category, brand = s.brand, competitor = s.competitor,
  reason = s.reason, run_id = s.run_id, prompt_version = s.prompt_version,
  context_version = s.context_version, model_version = s.model_version,
  updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
  search_term, decision, negative, match_type, intent, category, brand, competitor, reason,
  run_id, prompt_version, context_version, model_version, created_at, updated_at
) VALUES (
  s.search_term, s.decision, s.negative, s.match_type, s.intent, s.category, s.brand, s.competitor, s.reason,
  s.run_id, s.prompt_version, s.context_version, s.model_version, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
)
```

`prompt_version` and `context_version` are short hashes of the two files as sent. `model_version` is the exact model ID: the dated version pinned in `MODEL`, or the ID the response reports where the provider returns one.

## Schedule

CI runs the job once a day, a few hours after the Data Transfer's daily run, with the API keys in its secret variables. In GitLab that is a pipeline schedule plus a job that only runs on it; GitHub Actions does the same with an `on: schedule` trigger.

```yaml
# .gitlab-ci.yml
negatives-daily:
  image: python:3.12-slim
  resource_group: negatives           # one run at a time
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule" && $JOB == "negatives-daily"
  script:
    - pip install uv
    - uv sync --frozen
    - uv run python -m negatives --live
```

With more than one schedule in the project, give each schedule a variable (`JOB` above) and match it in the rule, or every schedule runs every scheduled job.

```yaml
# .github/workflows/negatives-daily.yml: the trigger and the lock
on:
  schedule:
    - cron: "0 7 * * *"               # UTC, a few hours after the transfer's daily run
concurrency:
  group: negatives                    # one run at a time
  cancel-in-progress: false
```

A GitLab schedule lives in the project settings, not in the repo, so list every job on a clock in `docs/scheduled-jobs.md` in your repo: when it runs, what it writes, how it alerts, how to check it fired. A unit test that fails when CI has a scheduled job the page does not list keeps the page true. Fire each new job once by hand: a job that never ran produces no error.

| Job | When | Writes | Alerts | Check it fired |
| --- | --- | --- | --- | --- |
| `negatives-daily` | daily, 07:00 UTC | `decisions`, `job_runs` | Slack on failure | today's `job_runs` row, status `success` |
| `review-sync` | daily, after `negatives-daily` | `reviews`, the review sheet | Slack on failure | today's `job_runs` row for `review-sync` |
| `accuracy-check` | daily, 09:00 UTC | `job_runs` (the score) | Slack under the floor, or no successful daily run | today's `job_runs` row for `accuracy-check` |

## Slack summary

Slack keeps the team informed without opening BigQuery: how many terms the job judged, how many negatives wait for review, and a link to the sheet. Post it daily, weekly or monthly (`SLACK["cadence"]`), depending on the size of the account and how often you add negatives. Read the numbers from BigQuery (`decisions`, `reviews`, `job_runs`), so the post reports what landed rather than what the job meant to do.

```
Negative keywords, last 7 days: 1,240 new search terms judged.
38 negatives and 12 terms to review wait in the sheet: <sheet link>
Accepted last week: 41 of 47.
```

Posting needs a Slack app with the `chat:write` scope, invited to the channel, or an incoming webhook. The token lives in CI secret variables.

## Production checklist

- **Dry by default**: the pipeline writes only with `--live`, so a forgotten flag is a dry run. A dry run still calls the model: it skips the writes, not the cost. `--limit` caps the input for a first run of a new prompt or query.
- **Safe reruns**: the anti-join and the per-batch MERGE make a rerun safe, as long as the staging rows are deduplicated first and a lock stops two runs writing at once. The CI lock is `resource_group` in GitLab and `concurrency` in GitHub Actions; a run started anywhere else first checks `job_runs` for a `running` row, ignoring one older than the longest run so a crash cannot lock the job for good.
- **Versions**: store the prompt, context and model version with every decision, and keep review decisions in their own table. When a rule changes, you can then reprocess the terms it touched without losing their review history.
- **Run IDs**: every run gets an ID, stamped on every row it writes and on its `job_runs` entry. One ID finds a run's rows and its log.
- **Fail soft**: a rate limit or a timeout is retried with a growing wait, up to `MAX_RETRIES` times. A batch that still fails leaves its terms unjudged for the next run, and the run moves on to the next batch.
- **Alerts**: a failed run posts to Slack, and so does a scheduled run that never started: the accuracy check looks for today's successful `negatives-daily` row and posts when there is none.
- **Service account**: the schedule runs as a service account, which needs read access to every dataset a query touches: `roles/bigquery.dataViewer` on the transfer dataset, `roles/bigquery.dataEditor` on your dataset, `roles/bigquery.jobUser` on the project, and the review sheet shared with it. A query that runs on your machine can still fail on the clock.
- **CI/CD**: fast tests run in CI on every push, including end-to-end runs of the pipeline on frozen fixtures with BigQuery and the model mocked. Tests against the real warehouse run before any SQL or schema change. A merge to main is the deploy, because the schedule runs the main branch, so a prompt change merges only after its gates pass.

## Tests

Fast, with no credentials, on every push:

- **Validation**: a term not in the batch is dropped; a term returned twice is dropped; a missing term stays unjudged; `ADD_NEGATIVE` without text fails the schema; a `PHRASE` off the safe list comes back `EXACT` on the full term; an `EXACT` with shortened text comes back as the full term.
- **Cut-off replies**: a cut-off batch splits in two; a single term that still fails is logged and left unjudged.
- **Dry run**: a run without `--live` makes no writes.
- **Prompt and config**: no `{placeholder}` survives filling; the categories in step 1 match the schema; `SAFE_PHRASES` matches the business context.
- **SQL**: every file loads with no placeholder left, and no project or dataset name is written anywhere but `config.py`.
- **End to end**: three frozen terms, one per decision, give three staged rows, one MERGE and a `job_runs` row with the right counts. A model error ends with status `failed` and an alert.
