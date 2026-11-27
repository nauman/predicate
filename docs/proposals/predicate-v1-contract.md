# `predicate/v1` contract (draft)

Refs #1. Status: **draft for review, nothing here is implemented.**

This draft fixes only what issue #1 already asks for, and lists everything
else as an open choice.

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
  `number`, `string`). The host supplies the values; a rule never fetches.
- `condition`: one node.
- Unknown keys are rejected, so the schema is closed.

Nodes:

| `op` | Other keys |
|---|---|
| `all`, `any` | `args`: a list of nodes |
| `not` | `arg`: one node |
| `eq`, `ne`, `gt`, `gte`, `lt`, `lte` | `fact`, `value` |
| `in` | `fact`, `values` |

## Fixed: what an evaluation returns

One of three statuses:

- `matched`
- `not_matched`
- `failed`: no answer. A missing fact, a fact of the wrong type, or an invalid
  rule gives `failed`, never `not_matched`. The host halts or escalates.

Values are never converted: `"12"` is not 12.

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
| Issue 460 asks to evaluate JSON Logic libraries, which already have Ruby and JavaScript engines. | Real alternative to a custom shape: adopt a restricted JSON Logic subset and get the browser evaluator for free. See choice 8. |
| Plan 46 says intake stays fixed-shape with no field builder, and that branching is the hand-off to calm.page. Issue 460 keeps conditional rules "proposed until audited". | Conditional form logic in Kuickr is a product decision that is not yet made in Kuickr's own docs. This contract can serve it, but does not settle it. |

What a rule decides (show a field, require it, route to HR) is the host's
business. The rule only answers yes or no.

Operators a form builder would normally offer, for reference when choosing:
is / is not, is empty / is filled, contains / starts with / ends with,
greater / less than, before / after (dates), is one of.

## Open choices

Nothing below is decided. Each can be settled when the implementation needs it.

1. **Optional facts.** Either every declared fact is required, or a fact can be
   marked optional and tested with an "is answered" operator. Kuickr forms
   need the second (see above).
2. **Failure inside `all`/`any`/`not`.** Either check all facts before
   evaluating (so logic never sees a failure), or let a failure propagate per
   node. Tied to choice 1.
3. **Trace.** Whether the outcome also lists each check (fact, expected,
   actual) and a reason for `failed`, and in what shape.
4. **Limits.** Maximum nodes, depth, list and string sizes: fixed by the spec,
   or set by the host.
5. **More types and operators.** `date` and `time` are needed for Kuickr
   fields. Text operators (`contains`, `starts_with`, `ends_with`) are common
   in form builders but not required by the leave example.
6. **Revision and digest.** Whether a rule carries a revision number or a
   content hash so an evaluation can be replayed.
7. **Ruby API and relation to the DSL.** Method names, and whether a rule can
   be registered alongside trusted Ruby predicates.

8. **Own shape or JSON Logic subset.** The shape above is easy to validate and
   read. A restricted JSON Logic subset has existing Ruby and JavaScript
   engines, at the cost of a less readable format, loose typing by default,
   and no built-in `failed` outcome (that layer would still be ours).

## Compared with #2 and #3

- #2 writes leaves as `field`/`operator`; #3 as `fact`/`op`. This draft uses
  `fact`/`op`.
- #3 accepts several names for the same key (`version`/`schema`,
  `condition`/`rule`/`expression`/`predicate`, `and`/`all`). This draft keeps
  one name each, which is what makes the schema closed.
- #3 also changes `core.rb`. This contract needs no change to the existing
  core.
