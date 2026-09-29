# Setup interview

The agent runs this before writing any code. Ask one question at a time, and offer a suggested answer with each (the Nike running default, or your best guess from what the user has said so far), so the user reacts instead of writing from scratch. Record every answer in the table at the bottom, then apply it to the file it names.

Never record a secret here. API keys and tokens go in `.env` locally and in CI secret variables.

## Account

1. **Account and campaigns**: Which Google Ads account does this run on? Which search campaigns are non-brand, and do brand searches have campaigns of their own? Which campaigns does the shared negative keyword list attach to?
   - Goes to: `BQ["customer_id"]` and `CAMPAIGN_IDS` in `config.py`.
   - Nike default: one account, brand campaigns apart, one shared list on every non-brand search campaign.
   - More than one account: the decisions table needs the account in its key, next to the search term.
2. **The offer**: What does the business sell, in the words its customers use? Which product categories should the model sort terms into?
   - Goes to: The offer in `prompts/business-context.md`, `{account}` and `{categories}` in `prompts/negatives.md`, and the `category` values in the output schema (`docs/pipeline.md`).
3. **Out of scope**: What does the business never sell or do? Which searches does it never want (jobs, used goods, repairs, free downloads)?
   - Goes to: Out of scope in `prompts/business-context.md`.
4. **Brand and competitors**: What are the brand and product line names, and who are the competitors? How should brand searches in the non-brand campaigns be handled, and competitor searches?
   - Goes to: Brand and competitors, and Account rules, in `prompts/business-context.md`.
   - Nike default: brand searches are `ADD_NEGATIVE` because the brand campaigns cover them; competitor searches are `TO_REVIEW`.
5. **Account rules**: Which calls does an experienced account manager on this account make without thinking? Which phrases are safe to block as phrase negatives, because no search the account wants contains them?
   - Goes to: Account rules in `prompts/business-context.md`, and `SAFE_PHRASES` in `config.py`.

## Numbers

6. **Conversion lag**: How many days after a click do most conversions arrive? The Days to conversion segment in Google Ads shows it.
   - Goes to: `STATS_FILTER["maturity_days"]`. Nike default: 7.
7. **Spend floor**: How much must a term spend, in the account's currency, before it is worth a model call and a review?
   - Goes to: `STATS_FILTER["min_cost"]`. Nike default: 5.0.
8. **Lookback**: How many days of stats should the query read?
   - Goes to: `STATS_FILTER["lookback_days"]`. Nike default: 30.

## Infrastructure

9. **Warehouse**: Which Google Cloud project? Which dataset does the Data Transfer write to, and which dataset should hold the pipeline's tables? Is the transfer running, at what time of day, and with what refresh window? Which service account will the schedule run as?
   - Goes to: `BQ` in `config.py`, which fills the table names in `sql/`.
10. **Model provider**: Gemini, Claude, OpenAI or another? Which model, pinned to a dated version where the provider has one? Does the provider offer structured output, prompt caching and a batch endpoint?
    - Goes to: `MODEL` in `config.py`, and the model client.
11. **CI and schedule**: GitLab or GitHub? What time should the daily run start, a few hours after the transfer has run? Who should failure alerts reach?
    - Goes to: the CI config, and `docs/scheduled-jobs.md` in your repo.
12. **Slack**: Which channel gets the summary, and how often: daily, weekly or monthly? A bot token or an incoming webhook?
    - Goes to: `SLACK` in `config.py`. The token goes in CI secret variables.

## Review

13. **Reviewers**: Who reviews the proposed negatives, and how often? Who is the domain expert who labels the gold set? Which Google Sheet holds the review?
    - Goes to: the export and sync jobs (`docs/review.md`). The gold set labels come from the domain expert only.
14. **Applying negatives**: Are approved negatives pasted into the shared list by hand, or added through the Google Ads API behind the same approval?
    - Goes to: the paste list or the API job (`docs/review.md`).

## Answers

The agent fills this in as the interview goes, and marks each row once the answer is applied.

| # | Topic | Answer | Applied to | Done |
| --- | --- | --- | --- | --- |
| 1 | Account and campaigns | | `config.py` | |
| 2 | The offer | | `prompts/business-context.md`, `prompts/negatives.md`, schema | |
| 3 | Out of scope | | `prompts/business-context.md` | |
| 4 | Brand and competitors | | `prompts/business-context.md` | |
| 5 | Account rules and safe phrases | | `prompts/business-context.md`, `config.py` | |
| 6 | Conversion lag | | `config.py` | |
| 7 | Spend floor | | `config.py` | |
| 8 | Lookback | | `config.py` | |
| 9 | Warehouse | | `config.py`, `sql/` | |
| 10 | Model provider | | `config.py`, model client | |
| 11 | CI and schedule | | CI config, `docs/scheduled-jobs.md` | |
| 12 | Slack | | `config.py` | |
| 13 | Reviewers | | review jobs | |
| 14 | Applying negatives | | paste list or API job | |
