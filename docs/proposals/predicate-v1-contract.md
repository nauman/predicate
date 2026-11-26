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

## Open choices

Nothing below is decided. Each can be settled when the implementation needs it.

1. **Optional facts.** Either every declared fact is required, or a fact can be
   marked optional and tested with a `present` operator.
2. **Failure inside `all`/`any`/`not`.** Either check all facts before
   evaluating (so logic never sees a failure), or let a failure propagate per
   node. Tied to choice 1.
3. **Trace.** Whether the outcome also lists each check (fact, expected,
   actual) and a reason for `failed`, and in what shape.
4. **Limits.** Maximum nodes, depth, list and string sizes: fixed by the spec,
   or set by the host.
5. **More types.** Dates are the likeliest addition; until then the host passes
   derived numbers such as `working_days`.
6. **Revision and digest.** Whether a rule carries a revision number or a
   content hash so an evaluation can be replayed.
7. **Ruby API and relation to the DSL.** Method names, and whether a rule can
   be registered alongside trusted Ruby predicates.

## Compared with #2 and #3

- #2 writes leaves as `field`/`operator`; #3 as `fact`/`op`. This draft uses
  `fact`/`op`.
- #3 accepts several names for the same key (`version`/`schema`,
  `condition`/`rule`/`expression`/`predicate`, `and`/`all`). This draft keeps
  one name each, which is what makes the schema closed.
- #3 also changes `core.rb`. This contract needs no change to the existing
  core.
