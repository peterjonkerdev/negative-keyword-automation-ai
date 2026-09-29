<!--
The business context for prompts/negatives.md. The pipeline strips comments like this one and
pastes the rest into the prompt's BUSINESS CONTEXT block at run time.

Replace the Nike running example below with your own account. The setup interview
(docs/setup-interview.md) collects what goes in each block. Keep the four headings.

The safe phrase list under Account rules must match SAFE_PHRASES in config.py: a unit test
compares the two.

Review changes to this file like code. Every edit changes decisions, so it passes the gold set
gates (docs/evals.md) before it merges.
-->

### The offer

Nike running: running shoes, apparel and accessories for men, women and kids, sold new through the online store.

- `shoes`: road running shoes, trail running shoes, racing shoes (including carbon-plated "super shoes"), track spikes.
- `apparel`: running tops, shorts, tights, jackets, sports bras.
- `accessories`: running socks, caps, headbands, running bags, water bottles.

Customers also say "trainers" and "runners" for running shoes.

### Out of scope

- Used, second-hand or refurbished products.
- Repairs, cleaning and custom printing.
- Treadmills, watches and fitness trackers, supplements, gym equipment.
- Training plans, coaching, race entries, race results, running clubs.
- Medical and injury advice.
- Jobs and careers.

### Brand and competitors

- Own brand: nike. Product lines: pegasus, vomero, vaporfly, alphafly, zoomx, air zoom.
- Competitors: adidas, asics, brooks, hoka, new balance, on (as "on running" or "on cloud"), puma, saucony, under armour.

### Account rules

- Brand searches: `ADD_NEGATIVE`, exact, the full term. The brand campaigns cover them.
- A size or fit search for a product the account sells ("running shoes wide fit", "running shoe size guide") is `LEAVE`.
- Price words (cheap, sale, discount, outlet) are no reason to block: judge the term as if the price word were not there. Sale items convert.
- Safe phrase negatives, the only phrases allowed as `PHRASE`: "marathon results", "clipart".
