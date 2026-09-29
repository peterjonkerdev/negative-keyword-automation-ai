# Review

Nothing reaches the account until a person accepts it. Start in a Google Sheet, and build a review app on the same tables once the team outgrows the sheet.

## Review sheet

An export writes each day's pending decisions to the sheet, and a sync job reads the reviewers' marks back into BigQuery. Two tabs:

- **Negatives**: one row per `ADD_NEGATIVE`. The reviewer marks each one accept or reject.
- **To review**: one row per `TO_REVIEW`. The reviewer decides block or leave, and for block, fills in the negative text and match type.

| Column | Filled by | Notes |
| --- | --- | --- |
| `search_term` | export | |
| `negative`, `match_type` | export | a reviewer may edit them before accepting |
| `reason` | export | the model's one line |
| `cost`, `clicks` | export | the lookback window, read fresh at export |
| `intent`, `category`, `competitor` | export | for sorting and filtering |
| `run_id` | export | hidden; the sync needs it |
| `review` | reviewer | accept or reject; block or leave on the second tab |
| `rejection_reason` | reviewer | one of the preset reasons, required for a reject |
| `comment` | reviewer | free text |
| `reviewer` | reviewer | who made the call |
| `applied` | whoever pastes the negatives | ticked once a negative is in the account |

## Sync

The sync runs before the export, in the same job, so a mark made since the last sync is never overwritten. It reads only rows with a `review`; blank rows stay pending.

Each marked row becomes a row in `reviews` (`sql/decisions.sql`), keyed on the search term and the run ID. Accept and block are stored as `BLOCK`, reject and leave as `LEAVE`, so one column answers "what happened to this term" for both tabs. An edited negative text or match type is stored as approved, and counts as a correction for the eval loop.

## Export checks

Before a row reaches the sheet, the export drops:

- **Already blocked**: a live negative already blocks the term, on the shared list or at campaign or ad group level.
- **Already on the list**: the same negative text is on the shared list, or accepted and waiting to be applied.
- **Converted since judged**: the term converted after the model judged it.

Read the live negatives through the Google Ads API: `shared_criterion` for the list, `campaign_criterion` and `ad_group_criterion` with `negative = TRUE` for the rest. Negatives do not match close variants, so compare by match type: an exact negative blocks the identical search, a phrase negative blocks searches that contain its words in order, a broad negative blocks searches that contain all its words in any order.

## Fresh conversions

The Data Transfer refreshes only recent days: its refresh window is 7 days by default and can be set up to 30. A conversion recorded after the window has passed never lands in the transfer tables, and the stats filter judged the term on what had landed.

So check conversions against fresh data before a row reaches the sheet: your own conversion data, or the Google Ads API (`metrics.conversions` from `search_term_view` over the lookback window). If approval takes days, check again when the negatives are applied, and drop any term that converted in between.

## Rejection reasons

Rejections, with a reviewer comment, flow into the eval loop, so the sheet offers a short list of preset reasons plus the free-text comment. "Wrong" gives the loop nothing to group. A starting list:

- We sell this
- This search converts
- Negative too broad
- Competitor or brand call
- Other (comment required)

Adjust the list as the failure modes in `docs/evals.md` settle.

## Applying negatives

Approved negatives go into the account in one of two ways, both behind the same approval:

- **By hand**: the export also writes a paste list of accepted negatives not yet applied, one per line in the match type's syntax: `[running man dance]` for exact, `"marathon results"` for phrase. Paste it into the shared negative keyword list, then tick `applied` on those rows so the sync sets `applied_at`.
- **Google Ads API**: a job reads accepted, unapplied rows and adds them to the shared list with the [Google Ads API](https://developers.google.com/google-ads/api/docs/start), for example through the [Python client](https://github.com/googleads/google-ads-python). It touches accepted rows only, is dry by default like the pipeline, sends a `validate_only` request before the real one, and sets `applied_at` for what went through.

Either way, check the list's size first: a shared list holds at most 5,000 negatives.

## Review app

When the sheet gets slow or the team grows, build an app on the same tables: it reads pending decisions from `decisions` and writes to `reviews`. The export checks, the preset reasons and the approval rule stay the same.
