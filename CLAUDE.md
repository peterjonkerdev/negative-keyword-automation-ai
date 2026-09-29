# CLAUDE.md

Instructions for the coding agent that builds this system with the user. The full guide: https://peterjonker.dev/posts/negative-keyword-automation-ai/

## The system

A daily batch job for one Google Ads account. It reads the new search terms from BigQuery, asks an LLM for one decision per term (`ADD_NEGATIVE`, `LEAVE` or `TO_REVIEW`), writes every decision to BigQuery and posts a summary to Slack. A person approves every negative before it reaches the account. A gold set scores every prompt change, and rejected negatives feed an eval loop that turns them into tested prompt fixes.

Nothing here runs as-is. The SQL, prompt, gold set and config are templates with Nike running as the worked example. You build the user's own version from them.

## Read order

1. `README.md`
2. `docs/architecture.md`: the seven parts, the tables, a code layout
3. `docs/setup-interview.md`
4. In build order: `docs/search-terms.md`, `docs/gold-set.md`, `docs/prompt.md`, `docs/pipeline.md`, `docs/review.md`, `docs/evals.md`
5. `docs/extensions.md`, once the core system runs

## Setup

Run `docs/setup-interview.md` before writing any code. One question at a time, each with a suggested answer. Record the answers in its Answers table, then apply each one to the file it names. Once setup is done, nothing Nike-specific is left in the prompt, the context, the gold set or the config.

## Build order

Finish each step, show the user the evidence (row counts, scores, a dry run's output), then start the next.

1. **Search terms query**: fill in `sql/new_search_terms.sql`, run it read-only, and compare clicks and spend with the Google Ads search terms report.
2. **Gold set**: about 100 terms from the account, labelled by the user, before any prompt work.
3. **Prompt**: `prompts/negatives.md` and `prompts/business-context.md`, scored on the gold set, several runs per version.
4. **Pipeline**: the six steps in `docs/pipeline.md`, tests first, dry by default, then the CI schedule.
5. **Review**: the sheet export, the sync back into BigQuery, the paste list.
6. **Evals**: the daily accuracy check, then the improvement loop.

## Non-negotiables

- Nothing reaches the Google Ads account without a person's approval. No code path adds a negative a person has not accepted.
- Dry by default: the pipeline writes only with `--live`.
- Every change to the prompt, the business context, the model or the batch size passes the gold set gates in `docs/evals.md` before it merges.
- Exact match by default, enforced in code: a `PHRASE` negative that is not on the safe list becomes `EXACT` on the full search term.
- Never commit secrets. API keys, service account keys and Slack tokens live in `.env` locally (gitignored) and in CI secret variables.

## Asking the user

Ask one question, with your best guess, before you:

- label a gold set term or change a label: the user is the domain expert, not you
- add or change an account rule, a safe phrase, or a brand or competitor name
- change a stats filter value, the batch size, the schedule or the Slack channel
- write to Google Ads, delete from BigQuery, or change a table's schema

When a gate fails or a number surprises you, report it with the numbers. Do not work around it.
