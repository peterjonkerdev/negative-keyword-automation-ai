# Prompt

This is where most of the time goes, and where the domain knowledge comes in: build the prompt, run it, test it against the gold set, improve it, and repeat until the output is what you need.

Many prompt structures work, and every part of this one is yours to change. `prompts/negatives.md` is one example that does. The gold set decides whether a change is better.

## Three decisions

The prompt answers one question per term (should the account block this search?) and returns one of three decisions:

- `ADD_NEGATIVE`: block it, with the negative's text and match type.
- `LEAVE`: a search the account wants, or one it can live with.
- `TO_REVIEW`: a call for a human review, including every term the model does not recognise.

## Metadata fields

Everything else it returns is metadata. The review sheet and the eval triage sort by it, and the evals score it.

| Field | Values |
| --- | --- |
| `intent` | `transactional`, `commercial`, `informational` or `navigational` |
| `category` | one of the offer's product categories, or `none` |
| `brand`, `competitor` | `true` or `false` |
| `reason` | one line a reviewer can check |

An unknown term (step 0) returns `null` for `intent`, `category`, `brand` and `competitor`, with the reason "unknown term".

## Structure

The structure matters more than the wording. Instructions go at the top, the business context at the bottom:

```markdown
## ROLE              the account, and the one question to answer per term
## STEP 0            unknown brand, product or slang? TO_REVIEW, "unknown term"
## STEP 1            classify: intent, category, brand, competitor
## STEP 2            decide, first match wins: ADD_NEGATIVE, LEAVE or TO_REVIEW
## STEP 3            negative text and match type: the full term, EXACT, by default
## OUTPUT            one JSON object per term, fields in a fixed order
## BUSINESS CONTEXT  the offer, out of scope, brand and competitors, account rules
```

## Rules

- **Room for unknown**: a model asked to pick one of three answers picks one, even for a brand it has never seen. Step 0 gives it a way out before any classification. It does not make the model know what it does not know, so put unfamiliar brand and product names in the gold set and measure how often they land in `TO_REVIEW`.
- **Rules inside their step**: each rule sits in the step where the model makes that call: brand and competitor detection in step 1, the decision order in step 2, match types in step 3. A rule in a preamble at the top is far from the moment the model uses it.
- **Exact by default**: a phrase negative blocks every search that contains it, which is where precision is lost. Phrase match needs a rule that proves the phrase is safe (the safe phrase list in Account rules), and the pipeline enforces the default in code rather than trusting the prompt (`docs/pipeline.md`).
- **One shared list**: every negative goes to one shared negative keyword list on the non-brand campaigns. That works only when every negative is unwanted in every campaign the list is attached to. A list holds at most 5,000 negatives, so watch its size and plan a second list before it fills.

## Levels

To place negatives per campaign or ad group instead of on one list:

1. Add the account structure to the business context: each campaign or ad group, and what it is for.
2. Add a `level` field to the output and to the schema: the campaign or ad group each negative belongs to.
3. Give every gold set case an expected level too, and score it next to the decision.

## Business context

The business context is the part each account writes for itself. Without it, the model judges search terms like a new analyst on day one: it knows what a negative keyword is and nothing about the business. `prompts/business-context.md` has four blocks:

- **The offer**: what the business sells, in the words its customers use.
- **Out of scope**: what it does not sell or do, and searches it never wants.
- **Brand and competitors**: the names that need their own handling.
- **Account rules**: the calls an experienced account manager makes without thinking.

The file lives apart from the prompt and is pasted into its last block at run time. Most of what changes between accounts is then that block, and the steps change only when the eval loop finds a mistake in them. Review the file like code: a stale product list is worse than none, because the model applies it with full confidence.

## Filling the prompt

| Placeholder | Filled by | Nike running value |
| --- | --- | --- |
| `{account}` | you, at setup | Nike running, which sells running shoes, apparel and accessories online |
| `{categories}` | you, at setup | shoes, apparel, accessories or none |
| `{business_context}` | the pipeline, every run | `prompts/business-context.md` |

- Fill with `str.replace`, not `str.format`: the JSON examples in the prompt contain braces.
- Strip the `<!-- -->` comments from the business context before pasting it in.
- A unit test fails when a `{placeholder}` survives filling, and when the categories in step 1 and the schema's `category` values differ.
- Replace every Nike example in the steps with one from your account, and keep those examples out of the gold set.

## Batch size

How many terms go into one call is a setting to test. 100 is a safe start. Bigger batches mean fewer calls and less repeated prompt, but past some size accuracy drops and long replies get cut off. Where that point sits depends on the model and its context window, and it moves with every model release.

Run the gold set at 100, 200 and 300 terms per call, several times each, and keep the largest size whose range matches the 100 run. `BATCH_SIZE` in `config.py` holds the result.

## Cost

If cost matters, cache the fixed part of the prompt (the steps and the business context) and send the daily run through the provider's batch endpoint. Both are billed below the standard rate, and nothing here needs an answer in seconds.

A cache matches only an identical prefix, so the filled prompt goes first in every call and the batch of terms after it, never inside it.
