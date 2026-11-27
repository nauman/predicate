# `predicate/v1` contract (draft)

Refs #1. Status: **draft with a standalone Ruby and JavaScript prototype.**

The first prototype uses the custom JSON shape. Both evaluators implement
`unanswered`, `eq`, `gt`, `not`, `all`, and `any` over booleans, dates and
safe integers. Other operators and types in the candidate schema are outside
this spike. The gem and Kuickr do not load the prototype.

Run both from this directory with `ruby prototype/check.rb` and
`node prototype/check.mjs`. Both read the same acceptance fixtures.

Companion files:

- `predicate-v1.schema.json`: JSON Schema (draft 2020-12) for the shape below.
- `predicate-v1.fixtures.json`: a few acceptance cases.

## Fixed: what a rule looks like

```json
{
  "schema": "predicate/v1",
  "id": "leave.requires_hr",
  "facts": {
    "working_days": { "type": "integer" }
  },
  "condition": { "op": "gt", "fact": "working_days", "value": 10 }
}
```

- `schema`: the contract version.
- `id`: a name for the rule.
- `facts`: the facts the rule reads, each with a type (`boolean`, `integer`,
  `number`, `string`, `date`) and an optional `required` flag (default true). The host supplies the values; a rule never fetches.
- `condition`: one node.
- Unknown keys are rejected, so the schema is closed.

Nodes:

| `op` | Other keys |
|---|---|
| `all`, `any` | `args`: a list of nodes |
| `unanswered` | `fact` |
| `not` | `arg`: one node |
| `eq`, `ne`, `gt`, `gte`, `lt`, `lte` | `fact`, `value` |
| `in` | `fact`, `values` |

## Fixed: what an evaluation returns

One of three statuses:

- `matched`
- `not_matched`
- `failed` when the rule is invalid or an evaluated condition lacks a usable value.

Before storing a rule, call Ruby’s `PredicatePrototype.valid?` or JavaScript’s
`valid(rule)`. The JSON Schema describes the wider draft grammar. Only the
semantic validator checks prototype support and fact declarations across the
entire rule, including skipped branches. Check
declarations, references, operator applicability and literal types. During
evaluation, visit branches from left to right. A reached failure ends the
evaluation immediately, including under `not`. The first match ends `any`
and the first non-match ends `all`. Skipped facts need no value.

Only an omitted optional key satisfies `unanswered`. A supplied, typed
`false` is answered. An omitted key fails ordinary comparisons even when
optional. Reading a missing required fact fails. An `unanswered` check on a
required fact is rejected at save time because it can never match.
Supplied nulls and empty strings fail boolean and date checks. Hosts preserve
omission when extracting answers. Host submission validation owns unconditional
field requirements.

Dates use four-digit years 0001–9999 and valid Gregorian calendar days in
exact YYYY-MM-DD form. Typed `gt` compares validated dates chronologically.
Integers in the prototype use the JavaScript safe integer range. Both entry
points receive parsed JSON values. Hosts must preserve numeric precision
when decoding input.

## What Kuickr intake forms need from this

Read from `Intellectaco/kuickr.co` at `90159f1` (`app/models/intake/field_schema`,
issue 460 and its comment, plan 46). These are observations, not decisions.

| Kuickr fact | Consequence for this contract |
|---|---|
| Field types are `text`, `long_text`, `email`, `phone`, `number`, `date`, `time`, `select`, `checkbox`. | `date` (`YYYY-MM-DD`) and `time` (`HH:MM`) are needed from the start, not later. Both are stored as strings that sort correctly. |
| An unanswered field is `nil` and is never stored. An unchecked checkbox is also "not answered". | "Not answered" is normal in a form. If a missing fact always gives `failed`, any rule over an optional field or a checkbox fails. The contract needs an "is answered / is empty" test, and must separate *not answered* from *fact unavailable or wrong type*. |
| `select` answers are one of a declared option list. | `in` and `eq` over strings cover it. |
| The field schema is versioned as `kuickr.intake_fields/1` and pinned to each submission with a digest. | A rule can be pinned the same way; the contract only needs to be hashable, which any JSON document is. |
| Form logic in the Jotform or Tally sense runs live in the browser (show, hide, require, skip) and again on the server at submit. | A second evaluator in JavaScript is required, driven by the same fixtures. The server result is the authoritative one. |
| Issue 460 asks to evaluate JSON Logic libraries, which already have Ruby and JavaScript engines. | Real alternative to a custom shape: adopt a restricted JSON Logic subset and reuse a JavaScript evaluator. The raw engines agreed on omission. Invalid dates and negated missing facts need additional validation. |
| Plan 46 says intake stays fixed-shape with no field builder, and that branching is the hand-off to calm.page. Issue 460 keeps conditional rules "proposed until audited". | Conditional form logic in Kuickr is a product decision that is not yet made in Kuickr's own docs. This contract can serve it, but does not settle it. |

What a rule decides (show a field, require it, route to HR) is the host's
business. The rule only answers yes or no.

Operators a form builder would normally offer, for reference when choosing:
is / is not, is empty / is filled, contains / starts with / ends with,
greater / less than, before / after (dates), is one of.

## Open choices

Nothing below is decided. Each can be settled when the implementation needs it.

1. **Trace.** Whether the outcome also lists each check (fact, expected,
   actual) and a reason for `failed`, and in what shape.
2. **Limits.** Maximum nodes, depth, list and string sizes: fixed by the spec,
   or set by the host.
3. **More types and operators.** `date` and `time` are needed for Kuickr
   fields. Text operators (`contains`, `starts_with`, `ends_with`) are common
   in form builders but not required by the leave example.
4. **Revision and digest.** Whether a rule carries a revision number or a
   content hash so an evaluation can be replayed.
5. **Ruby API and relation to the DSL.** Method names, and whether a rule can
   be registered alongside trusted Ruby predicates.

## Prototype checks

The shared suite contains 52 cases. Every invalid document must fail both
save-time validation and evaluation. The Ruby runner also checks five native
numeric inputs outside the parsed JSON fixture set.

**Browser form state.** Serve this directory with
`python3 -m http.server --bind 127.0.0.1` and open
`/prototype/browser-check.html`. Chrome 158 passed the shared suite and
eight DOM checks on a standalone form. Unchecked checkboxes and blank controls
produce omitted keys. A checked checkbox produces boolean true. A native date
control clears an impossible date assigned through its value setter. The
extractor then sees an empty value. A caller supplying that same invalid
string directly gets `failed`. This spike covers simple named controls.
Kuickr integration and partially typed native controls need separate testing.

**Restricted JSON Logic.** With `json-logic-rb` 0.4.0 and
`json-logic-engine` 5.0.9 available to their respective runtimes, run
`ruby prototype/check.rb --json-logic` and
`node prototype/check.mjs --json-logic`. Both engines passed the same 52
cases. Both backends validate the fixture document before translating it
to a restricted tree. Native `and`, `or` and `!` handle control flow.
Custom typed leaves implement `gt`, `eq` and `unanswered`; native
`throw` and `try` map invalid inputs to the failed outcome.

| Nonblank, non-comment implementation lines | Ruby | JavaScript | Total |
|---|---:|---:|---:|
| Shared validation | 50 | 39 | 89 |
| Custom evaluator including validation | 80 | 69 | 149 |
| JSON Logic adapter including validation | 88 | 67 | 155 |

Counts cover the corresponding validation and backend source files.
They exclude dependencies, runners and the browser harness. Translation
is included in the adapter count. The spike tests JSON Logic as an execution
backend for the same documents. Directly authoring JSON Logic would change
the validation and translation costs. Six lines provide little evidence for
choosing a format. The custom prototype currently achieves parity without
either engine dependency.

## When to revisit JSON Logic

Reconsider a restricted JSON Logic subset if it passes the shared fixtures
with less total implementation code, or if a host needs general expressions
or an existing visual rule builder. Each new custom operator would require
a precise contract and two implementations.

## Compared with #2 and #3

- #2 writes leaves as `field`/`operator`; #3 as `fact`/`op`. This draft uses
  `fact`/`op`.
- #3 accepts several names for the same key (`version`/`schema`,
  `condition`/`rule`/`expression`/`predicate`, `and`/`all`). This draft keeps
  one name each, which is what makes the schema closed.
- #3 also changes `core.rb`. This contract needs no change to the existing
  core.
