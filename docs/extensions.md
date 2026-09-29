# Extensions

Add these once the core system runs and its gates work. Each one is a change like any other: it passes the gold set gates in `docs/evals.md` before it merges.

## Web search

Every unknown term is a review a person does by hand. Web search gives the model the missing definition instead. There are two ways to add it:

- **Grounding inside the model call**: Gemini's [grounding with Google Search](https://ai.google.dev/gemini-api/docs/google-search) and Claude's [web search tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool) let the model search during the call itself and return the sources it used. One call and no extra client, with each search billed on top of the tokens.
- **A search API between two passes**: send the unknown terms to a search API like [Tavily](https://tavily.com/), then run them through the prompt a second time with the results attached. More code, but you decide exactly what the model sees.

Either way, search only the unknown terms (reason "unknown term"), not every term, and add a few of them to the gold set so the eval measures whether the lookup helped.

For the two-pass version:

- The second pass uses the same prompt, with each term's search result attached and step 0 told to judge a term on its result. A result that explains nothing leaves the term `TO_REVIEW`.
- Store the result's text and its source URL with the decision (two extra columns), so a reviewer sees what the model saw.
- A failed search leaves the term `TO_REVIEW`. The run never stops for one.

## Extra fields

The model already reads every search term that passes the filters, so it can return more than the decision in the same call. The template already asks for `intent`, `category`, `brand` and `competitor`: they sort the review sheet and the triage, and they land in the decisions table next to each decision. Reporting on intent by category, or on competitor presence, then needs no second pass over the data.

Add other fields the same way, such as a product line or the language. Each costs a few tokens per term, a column in `decisions`, and a flag score in the evals.

The fields describe the terms the model saw, not the whole account. The stats filter drops converted, new and low-spend terms before the call, so an account-wide share (the branded share of all searches, say) needs every term classified.
