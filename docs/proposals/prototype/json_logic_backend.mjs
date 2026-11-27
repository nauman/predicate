import {LogicEngine} from "json-logic-engine";
import {object, typed, valid} from "./validation.mjs";

const engine = new LogicEngine();
for (const operator of ["eq", "gt", "unanswered"]) {
  engine.addMethod("predicate." + operator, ([name, literal], {facts, declarations}) => {
    const present = Object.hasOwn(facts, name);
    if (!present && operator === "unanswered") return true;
    if (!present || !typed(facts[name], declarations[name].type)) {
      return engine.run({throw: "invalid_fact"});
    }
    if (operator === "gt") return facts[name] > literal;
    return operator === "eq" && facts[name] === literal;
  });
}

// The semantic validator restricts which operations can be emitted here.
function expression(node) {
  switch (node.op) {
    case "any": return {or: node.args.map(expression)};
    case "all": return {and: node.args.map(expression)};
    case "not": return {"!": [expression(node.arg)]};
    case "unanswered": return {"predicate.unanswered": [node.fact]};
    default: return {["predicate." + node.op]: [node.fact, node.value]};
  }
}

export function evaluate(rule, facts) {
  if (!valid(rule) || !object(facts)) return "failed";
  const status = {if: [expression(rule.condition), "matched", "not_matched"]};
  return engine.run({try: [status, "failed"]}, {facts, declarations: rule.facts});
}
