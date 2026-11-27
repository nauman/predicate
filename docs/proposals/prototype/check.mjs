import {readFileSync} from "node:fs";
import assert from "node:assert/strict";
import {evaluate as customEvaluate, valid} from "./evaluator.mjs";

const evaluate = process.argv.includes("--json-logic")
  ? (await import("./json_logic_backend.mjs")).evaluate : customEvaluate;
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
  assert.equal(evaluate(document, {}), "failed", why);
  checks++;
}
console.log(checks + " JavaScript cases passed");
