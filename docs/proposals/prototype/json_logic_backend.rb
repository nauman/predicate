# frozen_string_literal: true

require_relative 'validation'
gem 'json-logic-rb', '0.4.0'
require 'json_logic'

module PredicateJsonLogic
  module_function

  # Only these generated operations can reach the engine.
  def expression(node)
    case node['op']
    when 'any', 'all'
      operator = node['op'] == 'any' ? 'or' : 'and'
      { operator => node['args'].map { |child| expression(child) } }
    when 'not'
      { '!' => [expression(node['arg'])] }
    when 'unanswered'
      { 'predicate.unanswered' => [node['fact']] }
    else
      { "predicate.#{node['op']}" => node.values_at('fact', 'value') }
    end
  end

  %w[eq gt unanswered].each do |operator|
    JsonLogic.add_operation("predicate.#{operator}") do |(name, literal), context|
      facts, declarations = context
      if !facts.key?(name) && operator == 'unanswered'
        true
      elsif !facts.key?(name) || !PredicatePrototype.typed?(facts[name], declarations.fetch(name).fetch('type'))
        JsonLogic.apply({ 'throw' => 'invalid_fact' })
      elsif operator == 'gt'
        facts[name] > literal
      else
        operator == 'eq' && facts[name] == literal
      end
    end
  end

  def evaluate(rule, facts)
    return 'failed' unless PredicatePrototype.valid?(rule) && facts.is_a?(Hash)

    status = { 'if' => [expression(rule.fetch('condition')), 'matched', 'not_matched'] }
    JsonLogic.apply({ 'try' => [status, 'failed'] }, [facts, rule.fetch('facts')])
  end
end
