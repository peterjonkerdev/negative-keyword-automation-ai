# Evals

The gold set scores a prompt before it ships. Evals are how you measure and improve it over time: they keep scoring it after it ships, and turn rejections into fixes. The goal is not 100% accuracy. It is knowing where the prompt works, where it fails, and what to fix next.

## Daily accuracy check

A CI job scores the live prompt on the prod gold set every morning, and fails when decision accuracy drops under 90% (`GOLD_SET["daily_floor"]`). Nothing in the repo has to change for that to happen: a model alias can move to a new version, or someone edits the context without running the checks. Either one shows up the next morning, not after a week of bad negatives.

The threshold is a drift alarm, not the bar a prompt change has to clear. The job writes its score to `job_runs` (job `accuracy-check`), so the trend is one query, and a failure posts to Slack.

## Improvement loop

Rejections are where the fixes come from. Each round runs the same four steps:

1. **Triage**: a model labels each new rejection with a failure mode from a short fixed list and counts them. The most frequent mode is the next fix. Start with `COMPETITOR_MISSED`, `PRODUCT_READ_AS_UNRELATED`, `PHRASE_TOO_BROAD` and `OTHER`, and add a mode only when error analysis names a new one. The label goes in `reviews.failure_mode`.
2. **Error analysis**: one person, the domain expert, reads the rejections in the top group, with the reviewers' comments, and names the pattern behind them. [Hamel Husain](https://hamel.dev/)'s writing on evals is the clearest material on this step.
3. **Eval the fix**: the failing terms go into a dev gold set, each with its expected decision. Copy the production prompt, change only the step behind the failure, and run two gates, ten runs each, with the unchanged prompt as a control:
   - Dev gold set: did the change fix the failures?
   - Prod gold set: did it break anything that was passing?
4. **Approve**: the change can ship when it meets the release criteria below and a person approves it.

A coding agent runs everything but the judgment: the triage job, the runs, the tables of results, the commit. The part a person keeps is deciding which failure modes matter.

## Release criteria

A candidate ships when all of these hold over ten runs, against the control:

- **Dev gate**: the dev terms pass more often than under the control. The ones that pass ten runs out of ten graduate after the merge.
- **Prod gate**: the candidate's mean accuracy is within 2 points of the control's (`GOLD_SET["prod_tolerance_points"]`).
- **No new false positives**: no term that should stay comes out `ADD_NEGATIVE` more often than under the control, and no negative text or match type gets broader.
- **Must-pass cases**: a short list (your brand, your best-selling products) comes out right in every run.
- **Approval**: a person approves, and the commit carries both gates' results.

The same two gates decide every other change: a new model, a new provider, a rewritten context block, a bigger batch.

## Graduation

After the change merges, dev terms that passed ten runs out of ten move into the prod gold set. The rest wait in a backlog that is still scored with every run, so the hard cases stay visible.

## Metrics

Accuracy is one number. These five show where the prompt goes wrong:

- **False positives**: count the searches the prompt blocked that should stay, and check the negative text and match type as well as the label. A right `ADD_NEGATIVE` with a phrase that is too broad still blocks good searches, and accuracy alone hides it.
- **Review volume**: track how many terms land in `TO_REVIEW`. A prompt that sends every hard case to a person scores well and saves nobody time.
- **The flags**: score `intent`, `category`, `brand` and `competitor` as well as the decision. A flag can drift while the decision score holds steady.
- **Fresh labels**: add new terms labelled by someone who did not write the prompt, and sample `LEAVE` decisions as well as negatives. Rejections only show the negatives the prompt proposed wrongly, never the bad searches it let through. A weekly sample of `LEAVE` decisions on a spot-check tab of the review sheet covers this.
- **Accept rate**: the share of proposed negatives reviewers accept is a quick live check, but reviewers accept what looks right, so it does not replace the gold set.

When new batches stop producing new failure modes, the prompt is done for now.
