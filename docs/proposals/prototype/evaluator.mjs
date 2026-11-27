import {object, typed, valid} from "./validation.mjs";
export {valid} from "./validation.mjs";

class Invalid extends Error {}

export function evaluate(rule, facts) {
  if (!valid(rule) || !object(facts)) return "failed";
  function visit(node) {
    switch (node.op) {
      case "all": return node.args.every(visit);
      case "any": return node.args.some(visit);
      case "not": return !visit(node.arg);
      default: {
        const spec = rule.facts[node.fact];
        if (!Object.hasOwn(facts, node.fact)) {
          if (node.op === "unanswered" && spec.required === false) return true;
          throw new Invalid();
        }
        const value = facts[node.fact];
        if (!typed(value, spec.type)) throw new Invalid();
        if (node.op === "unanswered") return false;
        return node.op === "eq" ? value === node.value : value > node.value;
      }
    }
  }
  try {
    return visit(rule.condition) ? "matched" : "not_matched";
  } catch (error) {
    if (error instanceof Invalid) return "failed";
    throw error;
  }
}
