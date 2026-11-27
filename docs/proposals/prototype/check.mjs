import {readFileSync} from "node:fs";
import assert from "node:assert/strict";
import {evaluate, valid} from "./evaluator.mjs";

const fixtures = JSON.parse(readFileSync(new URL("../predicate-v1.fixtures.json", import.meta.url)));
let checks = 0;
for (const {rule, evaluations} of [fixtures, ...fixtures.scenarios]) {
  assert.ok(valid(rule), rule.id);
  for (const {facts, status} of evaluations) {
    assert.equal(evaluate(rule, facts), status, rule.id + " " + JSON.stringify(facts));
    checks++;
  }
}
for (const {document, why} of [...fixtures.invalid_documents, ...fixtures.invalid_rules]) {
  assert.equal(valid(document), false, why);
  checks++;
}
console.log(checks + " JavaScript cases passed");
