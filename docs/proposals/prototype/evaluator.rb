# frozen_string_literal: true

require_relative 'validation'

module PredicatePrototype
  class Invalid < StandardError; end

  module_function

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
