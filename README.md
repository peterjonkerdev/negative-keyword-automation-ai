# Negative Keyword Automation with AI

A template for a daily negative keyword system for Google Ads: search terms from BigQuery, an LLM with your business context, a gold set that scores every prompt change, and a person approving every negative.

Read the full guide: [Negative Keyword Automation with AI](https://peterjonker.dev/posts/negative-keyword-automation-ai/)

## Prerequisites

- A Google Ads account with non-brand search campaigns and real spend, and the [BigQuery Data Transfer for Google Ads](https://cloud.google.com/bigquery/docs/google-ads-transfer) running. Start the transfer first: its first load takes time.
- A Google Cloud project with BigQuery, and a service account for the scheduled job.
- An API key for an LLM provider with a structured output mode (Gemini, Claude, OpenAI or similar).
- Python 3.12 or later, with `uv`.
- A CI with scheduled jobs: GitLab pipeline schedules or GitHub Actions.
- Optionally, Slack, for the run summary.

## How to use it

This repo holds no code that runs as-is. It is a scaffold of docs, templates and one worked example (Nike running) that your coding agent reads to build your own version.

1. Clone the repo, or create a new repo from it.
2. Open it with Claude Code or Codex.
3. Ask the agent to run the setup interview in `docs/setup-interview.md`. It asks one question at a time and records your answers.
4. Build section by section in the order `CLAUDE.md` gives: the search terms query, the gold set, the prompt, the pipeline, the review, the evals. Check each against its doc before starting the next.

## What's inside

```
.
├── CLAUDE.md                  instructions for the coding agent
├── AGENTS.md                  points Codex to CLAUDE.md
├── README.md                  this file
├── config.example.py          filters, batch size, model, gold set gates
├── docs/
│   ├── setup-interview.md     the questions the agent asks first, and where the answers go
│   ├── architecture.md        the seven parts, the run-time flow, the tables, a code layout
│   ├── search-terms.md        the Data Transfer, the net-new query and the stats filter
│   ├── gold-set.md            building and scoring the gold set
│   ├── prompt.md              the prompt's structure, rules, batch size and cost
│   ├── pipeline.md            the six steps, the schedule, Slack, the production checklist
│   ├── review.md              the review sheet, the export checks, applying negatives
│   ├── evals.md               the daily accuracy check and the improvement loop
│   └── extensions.md          web search for unknown terms, extra fields
├── prompts/
│   ├── negatives.md           the prompt template
│   └── business-context.md    the account's context, pasted into the prompt at run time
├── sql/
│   ├── decisions.sql          the tables the pipeline writes
│   └── new_search_terms.sql   the daily fetch: net-new terms that pass the stats filter
└── gold_set/
    └── example.csv            about 20 labelled Nike running terms
```
