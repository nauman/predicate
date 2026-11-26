# frozen_string_literal: true

require_relative 'test_helper'

# Regressions for nauman/predicate#4 that 1.2.1 fixes without changing the
# public contract (raw predicate return values are still passed through).
class CoreEvaluationRegressionTest < Minitest::Test
  def test_nested_thread_safe_calls_do_not_deadlock
    core = Predicate::Core.new(:example, thread_safe: true)
    core.add_predicate(:inner) { true }
    core.add_predicate(:outer) { |state| core.call(:inner, state) }
    assert_equal true, core.call(:outer, {})
  end

  def test_nested_thread_safe_section_calls_do_not_deadlock
    core = Predicate::Core.new(:example, thread_safe: true)
    core.add_predicate(:inner) { true }
    core.add_section(:group) { |p| p[:outer] = ->(s) { core.call(:inner, s) } }
    assert_equal true, core.call_section(:group, :outer, {})
  end

  def test_exception_is_not_cached
    core = Predicate::Core.new(:example)
    attempts = 0
    core.add_predicate(:retryable) do
      attempts += 1
      raise 'temporary' if attempts == 1

      true
    end
    assert_equal false, core.call(:retryable, {})
    assert_equal true, core.call(:retryable, {})
  end

  def test_section_exception_is_not_cached
    core = Predicate::Core.new(:example)
    attempts = 0
    core.add_section(:group) do |p|
      p[:retryable] = lambda do |_|
        attempts += 1
        raise 'temporary' if attempts == 1

        true
      end
    end
    assert_equal false, core.call_section(:group, :retryable, {})
    assert_equal true, core.call_section(:group, :retryable, {})
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

  def test_raw_values_still_pass_through
    core = Predicate::Core.new(:example)
    core.add_predicate(:value) { |s| s[:value] }
    assert_equal 42, core.call(:value, { value: 42 })
  end
end
