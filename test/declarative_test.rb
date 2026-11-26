# frozen_string_literal: true

require_relative 'test_helper'
require 'timeout'

class DeclarativeTest < Minitest::Test
  include Predicate::Test::Helper

  def setup
    Predicate.clear_cache!
    Predicate.clear_registry!
  end

  def leave_document
    {
      'version' => Predicate::Declarative::SCHEMA_VERSION,
      'facts' => {
        'leave_days' => 'integer',
        'hr_required' => 'boolean'
      },
      'condition' => {
        'op' => 'and',
        'args' => [
          { 'op' => 'gt', 'fact' => 'leave_days', 'value' => 10 },
          { 'op' => 'eq', 'fact' => 'hr_required', 'value' => true }
        ]
      }
    }
  end

  def test_validate_and_match
    assert Predicate::Declarative.valid?(leave_document)
    result = Predicate::Declarative.evaluate(
      leave_document,
      { 'leave_days' => 12, 'hr_required' => true }
    )
    assert result.matched?
  end

  def test_missing_fact_is_failed
    result = Predicate::Declarative.evaluate(leave_document, { 'leave_days' => 12 })
    assert result.failed?
    assert_match(/missing fact/, result.error)
  end

  def test_typed_fact_is_failed
    result = Predicate::Declarative.evaluate(leave_document, { 'leave_days' => '12', 'hr_required' => true })
    assert result.failed?
    assert_match(/invalid fact type/, result.error)
  end

  def test_unknown_operator_and_closed_keys_are_rejected
    document = leave_document
    document['condition'] = { 'op' => 'eval', 'fact' => 'leave_days', 'ruby' => 'puts 1' }
    validation = Predicate::Declarative.validate(document)
    refute validation[:valid]
  end

  def test_core_explicit_outcomes_do_not_collate_errors
    core = Predicate::Core.new(:leave)
    core.add_predicate(:raw) { |_state| 'yes' }
    core.add_predicate(:broken) { |_state| raise 'database unavailable' }
    core.add_predicate(:missing) { |state| state[:required] }

    assert core.evaluate(:raw, {}).failed?
    assert core.evaluate(:broken, {}).failed?
    assert core.evaluate(:missing, {}).failed?
  end

  def test_nested_thread_safe_calls_do_not_deadlock
    core = Predicate::Core.new(:nested, thread_safe: true)
    core.add_predicate(:inner) { |_state| true }
    core.add_predicate(:outer) { |state| core.call(:inner, state) }

    Timeout.timeout(1) { assert core.call(:outer, {}) }
  end
end
