# frozen_string_literal: true

require_relative 'test_helper'

# Strict mode (1.3.0): a predicate that raises or does not exist halts the
# evaluation instead of reading as false — and as true once negated.
class StrictModeTest < Minitest::Test
  def setup
    Predicate.clear_registry!
  end

  def define(strict:)
    Predicate.define(:leave, strict: strict) do
      boom         { |_| raise ArgumentError, 'db down' }
      ok           { |_| true }
      not_boom     { |s| not_predicate(:boom).call(s) }
      not_typo     { |s| not_predicate(:hr_aproved).call(s) }
      none_boom    { |s| none_of(:boom).call(s) }
      any_ok_first { |s| any_of(:ok, :boom).call(s) }
      proc_boom    { |s| not_predicate(->(_) { raise 'inner' }).call(s) }
      section :hr do
        broken { |_| raise 'section down' }
      end
    end
  end

  def test_default_mode_is_unchanged
    core = define(strict: false)
    refute core.strict?
    assert_equal false, core.call(:boom, {})
    assert_equal false, core.call(:missing, {})
    assert_equal true, core.call(:not_boom, {})
    assert_equal true, core.call(:not_typo, {})
    assert_equal false, core.call_section(:hr, :broken, {})
    assert_equal false, core.call_section(:nope, :broken, {})
  end

  def test_strict_raises_when_predicate_raises
    core = define(strict: true)
    error = assert_raises(Predicate::EvaluationError) { core.call(:boom, {}) }
    assert_equal :boom, error.predicate_name
    assert_kind_of ArgumentError, error.cause
    assert_match(/db down/, error.message)
  end

  def test_strict_raises_for_undefined_predicate
    core = define(strict: true)
    error = assert_raises(Predicate::UndefinedPredicate) { core.call(:missing, {}) }
    assert_equal :missing, error.predicate_name
  end

  def test_strict_negation_of_failure_does_not_pass
    core = define(strict: true)
    error = assert_raises(Predicate::EvaluationError) { core.call(:not_boom, {}) }
    assert_equal :boom, error.predicate_name
    assert_raises(Predicate::EvaluationError) { core.call(:none_boom, {}) }
    assert_raises(Predicate::EvaluationError) { core.call(:proc_boom, {}) }
  end

  def test_strict_negation_of_typo_does_not_pass
    core = define(strict: true)
    error = assert_raises(Predicate::UndefinedPredicate) { core.call(:not_typo, {}) }
    assert_equal :hr_aproved, error.predicate_name
  end

  def test_strict_sections
    core = define(strict: true)
    assert_raises(Predicate::EvaluationError) { core.call_section(:hr, :broken, {}) }
    assert_raises(Predicate::UndefinedPredicate) { core.call_section(:hr, :nope, {}) }
    assert_raises(Predicate::UndefinedPredicate) { core.call_section(:nope, :broken, {}) }
  end

  def test_strict_keeps_short_circuit_and_normal_results
    core = define(strict: true)
    assert_equal true, core.call(:ok, {})
    assert_equal true, core.call(:any_ok_first, {})
  end

  def test_strict_failure_is_not_cached
    attempts = 0
    core = Predicate::Core.new(:example, strict: true)
    core.add_predicate(:flaky) do
      attempts += 1
      raise 'temporary' if attempts == 1

      true
    end
    assert_raises(Predicate::EvaluationError) { core.call(:flaky, {}) }
    assert_equal true, core.call(:flaky, {})
  end

  def test_strict_with_thread_safe_releases_lock_after_failure
    core = Predicate::Core.new(:example, strict: true, thread_safe: true)
    core.add_predicate(:boom) { raise 'x' }
    core.add_predicate(:ok) { true }
    assert_raises(Predicate::EvaluationError) { core.call(:boom, {}) }
    assert_equal true, core.call(:ok, {})
  end
end
