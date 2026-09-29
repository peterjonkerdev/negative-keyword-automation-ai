# Gold set

Build the gold set before the prompt. It is a file of search terms, each with the decision a domain expert would make, and it turns "the prompt looks good" into a number. Every prompt change is scored on it before it ships.

## Picking terms

Start with about 100 terms from the real account:

- Clear negatives and clear keeps in roughly equal numbers.
- Hard cases, spread evenly across categories: brand terms, competitors, product names the model may not know, how-to searches, terms with two meanings, products the account does not sell.
- Unfamiliar names: niche brands, new product names and slang from the account's own search terms. Step 0 of the prompt gives the model a way out for these, and only the gold set shows how often they land in `TO_REVIEW`.

A hundred copies of one easy case measure nothing. The domain expert labels every term: the agent can propose terms, not labels.

Keep the prompt's examples out of the gold set. A term in both scores itself.

## File format

A CSV, one row per term:

```csv
search_term,expected,why
how to prevent shin splints,ADD_NEGATIVE,"medical advice, no product in mind"
best running shoes men,LEAVE,"looking for running shoes the account sells"
hoka bondi 8,TO_REVIEW,"competitor product: the team decides competitor strategy"
```

- `expected`: `ADD_NEGATIVE`, `LEAVE` or `TO_REVIEW`.
- `why`: the expert's reason in one line. Error analysis reads it when a prompt gets the term wrong.

Add columns when you score more than the decision: `expected_negative` and `expected_match_type` (a right `ADD_NEGATIVE` with a phrase that is too broad still blocks good searches), the expected flags (`intent`, `category`, `brand`, `competitor`), `level` if negatives go per campaign or ad group, and `set` (`prod`, `dev` or `backlog`).

`gold_set/example.csv` holds about 20 Nike running terms, with two made-up brand names standing in for names the model cannot know. Replace all of them with terms from your account.

## Scoring

Score a prompt by running it over the set and comparing each decision with the expected one. Accuracy, the share that match, is the headline number. For negatives, two kinds of mistake matter, and they cost different things:

- **Blocking a good search**: the prompt says `ADD_NEGATIVE` for a term that should stay. It costs conversions, and you never see them, because the searches stop. The share of negatives that were right is called precision.
- **Missing a bad search**: the prompt lets through a term that should be a negative. It costs wasted spend, which stays visible in the search terms report. The share of bad searches caught is called recall.

```python
NEG = "ADD_NEGATIVE"

def score(decisions: dict[str, str], gold: dict[str, str]) -> dict[str, float]:
    # A term the model did not return counts as a wrong answer.
    pairs = [(decisions.get(term, "MISSING"), expected) for term, expected in gold.items()]
    tp = sum(d == NEG and e == NEG for d, e in pairs)
    fp = sum(d == NEG and e != NEG for d, e in pairs)
    fn = sum(d != NEG and e == NEG for d, e in pairs)
    return {
        "accuracy": sum(d == e for d, e in pairs) / len(pairs),
        "precision": tp / max(tp + fp, 1),
        "recall": tp / max(tp + fn, 1),
    }
```

Store every scored run with its prompt, context and model versions, so each score traces back to the setup that produced it.

## Repeated runs

One run does not show reliability. The same prompt on the same terms gives slightly different answers each time, and a score can move a few points between runs with nothing changed.

- Run each prompt version several times and compare the ranges (lowest to highest), not single scores.
- When two versions' ranges overlap, the comparison is unresolved: run more, or treat the two as equal.
- The release gates use ten runs per version (`docs/evals.md`).

## Prod and dev sets

Once the system runs, the gold set is used in two ways:

- **Prod set**: scored every day on the live prompt, to catch a drop. It starts as the first set and grows only with terms that pass ten runs out of ten.
- **Dev set**: the terms behind a failure the eval loop is fixing, used to test a prompt change before it ships. Terms that do not pass yet wait in a backlog that is still scored with every run.

`docs/evals.md` covers the daily check and how terms move between the sets.

## Upkeep

When the business changes (a new product line, a competitor that stops being one), re-label the terms it touches in the same change as the business context. A stale label is a wrong test.
