# Why the price table is not the list price

`sweep.spec`'s `prices` block is a CLOSED schema (`as_of`, `margin`, `rates`
and nothing else), so this note cannot live in the spec file. It belongs to
`sweep_openrouter_pilot.json` and `sweep_openrouter.json`.

**The rates are `deepseek/deepseek-chat`'s list price multiplied by 1.2396.**

MEASURED 2026-09-28 against a real OpenRouter turn: **$0.00472779 billed**
against **$0.00381386 derived** from the list price — the table understated by
24.0 %. The cause is that OpenRouter routes to third-party providers whose
effective rate is higher, and the request carries nothing that says which one
served it, so a client-side table cannot be exact.

Two fixes exist and only one is available here:

* **pin the upstream provider** — OpenRouter supports a `provider` routing
  field, but `dsh`'s `openai-completions` adapter has no way to send one, and
  adding one would be a change to a vendored harness;
* **raise the table to the observed effective rate** — done.

Raising is the conservative direction. A derived figure is what §11.2.1 lets
bind a ceiling, and a ceiling that binds slightly early is safe while one that
binds late spends credit that is not there. `margin: 0.15` is carried on top
of this, as §11.2.1 requires, and is a separate allowance.

    list    input 0.2574   output 1.0287    USD / Mtok
    table   input 0.319073 output 1.275177  USD / Mtok   (x 1.2396)

**This is an estimate, not billing.** OpenRouter's own figure is the truth and
is read with:

    curl -s -H "Authorization: Bearer $OPENROUTER_API_KEY" \
         https://openrouter.ai/api/v1/credits

---

## Second measurement, 2026-09-28 20:45 — the ratio is not constant

The pilot's first real turn on a VM: **9 260 input + 279 output** tokens,
billed **$0.002670531** (OpenRouter `/credits`, before minus after).

    list price   9260*0.2574/1e6 + 279*1.0287/1e6   = $0.00267053
    this table   9260*0.319073/1e6 + 279*1.275177/1e6 = $0.00331039

**The list price was exact to five decimal places, and this table overstates
by 24 %** — the opposite direction from the measurement above.

Both observations are real. The conclusion is not "one of them was wrong" but
that **there is no single effective rate**: OpenRouter picks a third-party
provider per request and the response says nothing about which, so a
client-side table has per-request variance of at least ±24 % either way.

The table is LEFT at ×1.2396. Overstating makes a derived ceiling bind early,
which is the safe failure; understating spends credit that is not there. But
do not quote a derived total as spend. `/credits` is the only truth.

---

## 2026-09-29: the flash table, set from a measured 161-sweep endpoint

The table above is `deepseek/deepseek-chat`'s. The sweep runs
**`deepseek/deepseek-v4-flash`**, whose rates were
`input 0.060616, output 0.121109, cache_read 0.0` — not that model's list
price, and **`cache_read: 0.0` was the expensive part**.

**Measured**, one real endpoint (`comments_index`, GCP box, 2026-09-29):
OpenRouter `/credits` moved `81.308127414 -> 81.568798544` = **$0.260671**,
for `input 90 161`, `output 30 387`, **`cache_read 6 908 416`**. The old table
derived **$0.009145** — understating by **×28.5**. A long single turn re-reads
its whole context every step, so cache reads are ~98 % of the tokens and were
priced at nothing.

**Reconciled against the published rates rather than a guess.** OpenRouter
publishes for this model `prompt 0.14`, `completion 0.28`,
`input_cache_read 0.028` USD/Mtok. Pricing all three classes at list gives
$0.214567 against $0.260671 measured — list understates by **×1.2149**, which
is the same effective-rate gap the ×1.2396 multiplier above was measured for.
So the published figure and the measurement AGREE; an earlier reading of
"~$0.036/Mtok implied cache-read" was wrong because it charged the whole gap to
cache reads while input and output were under-priced too.

**The table is list × 1.2396**, keeping both conventions:

    list    input 0.14      output 0.28      cache_read 0.028    USD / Mtok
    table   input 0.173544  output 0.347088  cache_read 0.034709 (x 1.2396)

Derived for the measured endpoint: **$0.265977 vs $0.260671 actual — +2.04 %**,
overstating, which is the direction this file already argues for. `margin: 0.15`
still sits on top, so the reported figure is $0.305873.

**What this changes about the sweep's shape.** At ~$0.26/endpoint the 161-run is
**≈ $42 of model spend** against **≈ $4.3 of GCP** — model cost is ~10× box
cost, so `cloud.max_concurrent_vms` is no longer the binding lever and
`/credits` is the number to watch while widening.

### Second measurement, same day: the table cannot be trusted as a per-endpoint cost

The +2.04 % above was fitted to ONE endpoint. A second real endpoint
(`comments_index` again, 2026-09-29 04:01, also `submitted: true`) does not fit
it, and not by a little:

| run | real $ | list $ | table $ | real/list | table/real |
|---|---|---|---|---|---|
| 00:20 | 0.26067 | 0.21457 | 0.26598 | 1.215 | **1.02** |
| 04:01 | 0.39923 | 0.68007 | 0.84301 | 0.587 | **2.11** |

Reported tokens: run 1 `input 90 161 / output 30 387 / cache_read 6 908 416`;
run 2 `input 957 913 / output 26 900 / cache_read 19 229 507`. The blended
actual rate moves from **$0.03709/Mtok** to **$0.01975/Mtok** — 1.88× — so the
counts `dsh` reports do not stand in a fixed relation to what OpenRouter bills,
and **no single multiplier can fit both runs**. Fitting one to either run
guarantees being wrong about the other.

**What this table is, therefore.** It is built on the model's published rates
and it errs high, which is the direction this file argues for, and it is a
vast improvement on `cache_read: 0.0` (which understated run 1 by ×28.5 and
reported a genuinely-spending sweep as `cost: null`). It is **not** a
per-endpoint cost control and must not be used as one. `/credits` before and
after is the only truth, and the real per-endpoint figure measured so far is
**$0.26–$0.40, mean ≈ $0.33** — so 161 endpoints is **≈ $53 of model spend**.

**Open — not fixed here.** Why the counts drift is unresolved and is a defect in
the accounting rather than in the price table. One candidate found while
looking: `agentd._observe_usage` reads `payload["tokens"]`, which
`deepseek._on_usage` sets to `tracker.total` (already cumulative), and calls
`observe_delta()` on it because the adapter declares `cumulative: false` — so
agentd's own independent counter sums cumulative snapshots. That counter feeds
`AgentRun.agentd_tokens` (a comparison figure) and not §11.1's row, so it does
not explain the row's drift, but it is the same confusion in the same seam and
whoever fixes one should look at the other.
