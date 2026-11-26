# `predicate/v1` contract (draft)

Refs #1. Status: **draft for review, nothing here is implemented.** It settles
the points where the proposal in #2 and the implementation in #3 disagree.

Companion files:

- `predicate-v1.schema.json`: JSON Schema (draft 2020-12) for a rule document.
- `predicate-v1.fixtures.json`: acceptance cases every implementation must pass.

## 1. What a rule is

A rule is data that answers one yes/no question about facts the host supplies.
It cannot run code, fetch anything, or grant permission.

```json
{
  "schema": "predicate/v1",
  "id": "leave.requires_hr",
  "revision": 1,
  "facts": {
    "working_days": { "type": "integer" },
    "employment":   { "type": "string" }
  },
  "condition": {
    "op": "all",
    "args": [
      { "op": "gt", "fact": "working_days", "value": 10 },
      { "op": "not", "arg": { "op": "in", "fact": "employment", "values": ["contractor", "intern"] } }
    ]
  }
}
```

| Key | Required | Meaning |
|---|---|---|
| `schema` | yes | Exactly `"predicate/v1"`. |
| `id` | yes | Dotted lowercase name, e.g. `leave.requires_hr`. |
| `revision` | yes | Integer ≥ 1. The author bumps it on every change. |
| `description` | no | Free text for humans, ≤ 512 chars. Never evaluated. |
| `facts` | yes | Every fact the rule reads, with its type. 1–32 entries. |
| `condition` | yes | One node (below). |

There is one spelling for everything. `version`, `rule`, `expression`,
`predicate`, `field`, `operator`, `and`, `or` are all rejected as unknown.

## 2. Nodes

Every node is an object with an `op`. There are four shapes and no others.

| Shape | `op` | Other keys |
|---|---|---|
| Group | `all`, `any` | `args`: 1–16 nodes |
| Negation | `not` | `arg`: one node |
| Comparison | `eq`, `ne`, `gt`, `gte`, `lt`, `lte` | `fact`, `value` |
| Membership | `in` | `fact`, `values`: 1–100 unique literals |

A literal is a boolean, a number, or a string of at most 256 characters.
`null`, arrays and objects are not literals.

## 3. Types

Fact types: `boolean`, `integer`, `number`, `string`.

| Fact type | Accepts as fact value and as literal | Operators |
|---|---|---|
| `boolean` | `true`, `false` | `eq`, `ne` |
| `integer` | a JSON number with no fractional part | all comparisons, `in` |
| `number` | any finite JSON number | all comparisons, `in` |
| `string` | a string ≤ 256 chars | `eq`, `ne`, `in` |

- No conversion, ever. `"12"` is not 12; `1` is not `true`.
- `12.0` is not an integer.
- Strings compare by exact code points. No case folding, no trimming, and no
  ordering (`gt` on a string is a validation error).

## 4. Three stages, and only the first two can fail

This is the main design decision. All failure happens **before** the condition
runs, so the condition itself is ordinary two-valued logic.

1. **Validate the document.** Structure (the JSON Schema) plus the semantic
   checks in section 6. Done once, when the rule is authored or loaded.
2. **Check the facts.** Every declared fact must be supplied, non-null, and of
   its declared type. All problems are collected, not just the first.
3. **Evaluate.** With a valid document and valid facts this cannot fail. Every
   leaf is evaluated (no short-circuit), so the trace is complete and the
   result does not depend on argument order.

Consequences:

- `not` over a missing fact can never come out `true`: stage 2 already failed.
- There is no three-valued logic to define for `all`/`any`/`not`.
- Facts the host supplies but the rule does not declare are ignored and never
  appear in the outcome. The host may pass one wide fact bag to many rules.

## 5. Outcome

```json
{
  "schema": "predicate/v1/outcome",
  "status": "matched",
  "rule": { "id": "leave.requires_hr", "revision": 1, "digest": "sha256:9f2c…" },
  "checks": [
    { "path": "/condition/args/0", "op": "gt", "fact": "working_days",
      "expected": 10, "actual": 12, "result": true },
    { "path": "/condition/args/1/arg", "op": "in", "fact": "employment",
      "expected": ["contractor", "intern"], "actual": "permanent", "result": false }
  ],
  "errors": []
}
```

- `status` is exactly one of `matched`, `not_matched`, `failed`.
- `failed` means **no answer**. The host must halt or escalate; it must not
  take the false branch.
- `checks` lists every leaf, addressed by JSON Pointer. It is empty when
  `status` is `failed`.
- `errors` is empty unless `status` is `failed`. Each entry has `code`, and
  where relevant `fact` and `path`, plus a human `message`.
- `digest` is SHA-256 over the rule's canonical JSON (RFC 8785). Storing the
  digest and the declared facts is enough to replay an evaluation.

Error codes (closed list):

| Stage | Code |
|---|---|
| Document | `invalid_document`, `unsupported_schema`, `undeclared_fact`, `unused_fact`, `value_type_mismatch`, `operator_not_allowed`, `limit_exceeded` |
| Facts | `fact_missing`, `fact_type_mismatch` |

## 6. Checks the JSON Schema cannot express

The schema file catches structure. The validator must also enforce:

- every `fact` a node names is declared (`undeclared_fact`);
- every declared fact is used at least once (`unused_fact`), so a rule never
  demands facts it does not read;
- each literal has the fact's type (`value_type_mismatch`);
- the operator is allowed for the fact's type (`operator_not_allowed`);
- at most 64 nodes and depth 8, and the document is at most 16 KB before
  parsing (`limit_exceeded`).

## 7. Ruby surface (sketch)

```ruby
report = Predicate::Declarative.validate(document)  # => valid? / errors, never raises
rule   = Predicate::Declarative.load(document)      # frozen Rule; raises InvalidDocument
out    = rule.evaluate(facts)                       # => Outcome; never raises on bad facts
out.status    # :matched / :not_matched / :failed
out.matched?  # true only for :matched
out.to_h      # the JSON above
```

- Separate from `Predicate::Core`: no cache, no registry, no `method_missing`.
  Evaluation is pure, so there is nothing to invalidate.
- `Outcome` has no `==` against symbols and no truthiness shortcut besides
  `matched?`, so a `failed` outcome cannot be mistaken for false by accident.
- No new dependency. `json` and `digest` are already used.

## 8. Differences from #2 and #3

| Topic | #2 (doc) | #3 (code) | This draft |
|---|---|---|---|
| Version key | `schema` | `version` or `schema`; `"1"`, `1` also accepted | `schema`, exact string |
| Root key | `condition` | `condition`/`rule`/`expression`/`predicate` | `condition` |
| Leaf keys | `field`, `operator` | `fact`, `op` | `fact`, `op` |
| AND/OR names | not fixed | `and`/`all`, `or`/`any` | `all`, `any` |
| Fact declarations | implied | `facts` as object or array, plus `fact_types` | `facts` object, type required |
| Presence operators | none | `present`, `missing` | none in v1 (see 9) |
| Failure inside logic | "define before implementation" | per-node, short-circuit | cannot occur (section 4) |
| Limits set by document | no | `max_nodes`, `max_depth` keys | fixed by the spec |
| Trace | "reason and checks" | status and one error string | full `checks` + coded `errors` |
| Core changes | none | rewrites `core.rb` | none |

## 9. Open decisions

1. **Optional facts.** v1 says every declared fact is required. If a rule must
   ask "was a manager supplied?", the host can pass a boolean fact
   `has_manager`. Alternative: `"required": false` plus a `present` operator,
   at the cost of bringing back per-node failure rules.
2. **Dates.** Not a type in v1; the host passes derived integers
   (`working_days`). A `date` type (ISO 8601, ordered) is the likeliest v1.1
   addition.
3. **Unused declared facts** are an error here. Relaxing it to a warning is
   harmless if authoring tools prefer to declare a shared fact set.
4. **Bridge to the DSL.** Whether a loaded rule can be registered as a named
   predicate on a strict `Core` (1.2.2) so trusted Ruby can compose it. Not
   needed for the first cut.
5. **Where it ships.** New files only, additive, so it can be a 1.3.0 minor.
   The boolean contract change from #4 stays a separate 2.0 question.
