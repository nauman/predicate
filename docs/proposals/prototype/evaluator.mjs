const object = value => value !== null && typeof value === "object" && !Array.isArray(value);
const name = value => typeof value === "string" && value.length > 0;
const keys = (value, ...names) => object(value) && Object.keys(value).length === names.length &&
  names.every(key => Object.hasOwn(value, key));

function typed(value, type) {
  if (type === "boolean") return typeof value === "boolean";
  if (type === "integer") return Number.isSafeInteger(value);
  if (type !== "date" || typeof value !== "string" || value.length !== 10 ||
      !/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith("0000")) return false;
  const date = new Date(value + "T00:00:00Z");
  return Number.isFinite(date.valueOf()) && date.toISOString().slice(0, 10) === value;
}

function validNode(node, declarations) {
  if (!object(node)) return false;
  switch (node.op) {
    case "any":
    case "all":
      return keys(node, "op", "args") && Array.isArray(node.args) && node.args.length > 0 &&
        node.args.every(arg => validNode(arg, declarations));
    case "not":
      return keys(node, "op", "arg") && validNode(node.arg, declarations);
    default: {
      if (!name(node.fact) || !Object.hasOwn(declarations, node.fact)) return false;
      if (node.op === "unanswered") return keys(node, "op", "fact");
      const {type} = declarations[node.fact];
      return keys(node, "op", "fact", "value") &&
        (node.op === "eq" || (node.op === "gt" && type !== "boolean")) && typed(node.value, type);
    }
  }
}

export function valid(rule) {
  return keys(rule, "schema", "id", "facts", "condition") && rule.schema === "predicate/v1" &&
    name(rule.id) && object(rule.facts) && Object.keys(rule.facts).length > 0 &&
    Object.entries(rule.facts).every(([key, spec]) => name(key) &&
      (keys(spec, "type") || keys(spec, "type", "required")) &&
      ["boolean", "integer", "date"].includes(spec.type) &&
      (!Object.hasOwn(spec, "required") || typeof spec.required === "boolean")) &&
    validNode(rule.condition, rule.facts);
}

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
