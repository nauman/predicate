# frozen_string_literal: true

require 'date'

module PredicatePrototype
  class Invalid < StandardError; end

  module_function

  def keys?(value, *names)
    value.is_a?(Hash) && value.size == names.size && names.all? { |name| value.key?(name) }
  end

  def name?(value)
    value.is_a?(String) && !value.empty?
  end

  def typed?(value, type)
    case type
    when 'boolean' then value == true || value == false
    when 'integer'
      value.is_a?(Numeric) && value.abs <= 9_007_199_254_740_991 && value == value.to_i
    when 'date'
      return false unless value.is_a?(String) && /\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/.match?(value)

      year, month, day = value.split('-').map(&:to_i)
      year.positive? && month.positive? && day.positive? && Date.valid_date?(year, month, day, Date::GREGORIAN)
    end
  end

  def valid?(rule)
    return false unless keys?(rule, 'schema', 'id', 'facts', 'condition')
    return false unless rule['schema'] == 'predicate/v1' && name?(rule['id'])

    declarations = rule['facts']
    return false unless declarations.is_a?(Hash) && !declarations.empty?

    declarations.all? do |name, spec|
      name?(name) &&
        (keys?(spec, 'type') || keys?(spec, 'type', 'required')) &&
        %w[boolean integer date].include?(spec['type']) && typed?(spec.fetch('required', true), 'boolean')
    end && valid_node?(rule['condition'], declarations)
  end

  def valid_node?(node, declarations)
    return false unless node.is_a?(Hash)

    case node['op']
    when 'all', 'any'
      args = node['args']
      keys?(node, 'op', 'args') && args.is_a?(Array) && !args.empty? && args.all? { |arg| valid_node?(arg, declarations) }
    when 'not'
      keys?(node, 'op', 'arg') && valid_node?(node['arg'], declarations)
    else
      spec = declarations[node['fact']]
      return false unless spec
      return keys?(node, 'op', 'fact') if node['op'] == 'unanswered'

      keys?(node, 'op', 'fact', 'value') &&
        (node['op'] == 'eq' || (node['op'] == 'gt' && spec['type'] != 'boolean')) &&
        typed?(node['value'], spec['type'])
    end
  end

  def evaluate(rule, facts)
    return 'failed' unless valid?(rule) && facts.is_a?(Hash)

    visit(rule['condition'], rule['facts'], facts) ? 'matched' : 'not_matched'
  rescue Invalid
    'failed'
  end

  def visit(node, declarations, facts)
    case node['op']
    when 'all' then node['args'].all? { |arg| visit(arg, declarations, facts) }
    when 'any' then node['args'].any? { |arg| visit(arg, declarations, facts) }
    when 'not' then !visit(node['arg'], declarations, facts)
    else
      name = node['fact']
      spec = declarations.fetch(name)
      unless facts.key?(name)
        return true if node['op'] == 'unanswered' && !spec.fetch('required', true)

        raise Invalid
      end
      value = facts[name]
      raise Invalid unless typed?(value, spec['type'])
      return false if node['op'] == 'unanswered'

      node['op'] == 'eq' ? value == node['value'] : value > node['value']
    end
  end
  private_class_method :visit
end
