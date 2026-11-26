# frozen_string_literal: true
require_relative 'test_helper'

class CoreEvaluationRegressionTest < Minitest::Test
  def test_nested_thread_safe_calls
    core = Predicate::Core.new(:example, thread_safe: true)
    core.add_predicate(:inner) { true }
    core.add_predicate(:outer) { |state| core.call(:inner, state) }
    assert_equal true, core.call(:outer, {})
  end

  def test_boolean_contract
    core = Predicate::Core.new(:example)
    core.add_predicate(:nil_value) { nil }
    core.add_predicate(:truthy) { "yes" }
    assert_equal false, core.call(:nil_value, {})
    assert_equal true, core.call(:truthy, {})
  end

  def test_exception_is_not_cached
    core = Predicate::Core.new(:example)
    attempts = 0
    core.add_predicate(:retryable) do
      attempts += 1
      raise "temporary" if attempts == 1
      true
    end
    assert_equal false, core.call(:retryable, {})
    assert_equal true, core.call(:retryable, {})
  end

  def test_section_replacement_invalidates_cache
    core = Predicate::Core.new(:example)
    core.add_section(:group) { |p| p[:ready] = ->(_) { true } }
    assert_equal true, core.call_section(:group, :ready, {})
    assert_equal true, core.call(:ready, {})
    core.add_section(:group) { |p| p[:ready] = ->(_) { false } }
    assert_equal false, core.call_section(:group, :ready, {})
    assert_equal false, core.call(:ready, {})
  end

  def test_direct_and_section_cache_names_do_not_collide
    core = Predicate::Core.new(:example)
    core.add_predicate(:group_ready) { true }
    core.add_section(:group) { |p| p[:ready] = ->(_) { false } }
    assert_equal true, core.call(:group_ready, {})
    assert_equal false, core.call_section(:group, :ready, {})
  end
end
