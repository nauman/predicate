# frozen_string_literal: true

require 'ostruct'
require_relative 'test_helper'

# Strict mode through Predicate::ModelIntegration (`model.some_predicate?`).
class ModelIntegrationStrictTest < Minitest::Test
  def setup
    Predicate.clear_registry!
  end

  def build_model(strict:)
    Predicate.define(:leave_request, strict: strict) do
      long_leave  { |s| s[:working_days] > 10 }
      blocked     { |s| s.fetch(:blocked) }
      not_blocked { |s| not_predicate(:blocked).call(s) }
      not_typo    { |s| not_predicate(:hr_aproved).call(s) }
      section :hr do
        needs_hr { |s| s[:working_days] > 10 }
      end
    end

    Class.new do
      include Predicate::ModelIntegration

      def self.model_name
        OpenStruct.new(underscore: 'leave_request')
      end

      def initialize(attributes = {})
        @attributes = attributes
      end

      attr_reader :attributes
    end
  end

  def test_default_mode_is_unchanged
    model = build_model(strict: false).new(working_days: 12)
    assert_equal true, model.long_leave?
    assert_equal false, model.blocked?
    assert_equal true, model.not_blocked?
    assert_equal true, model.not_typo?
    assert_equal false, model.no_such_predicate?
    assert_equal false, model.needs_hr?
  end

  def test_strict_normal_results
    klass = build_model(strict: true)
    assert klass.load_predicates!.strict?
    assert_equal true, klass.new(working_days: 12, blocked: false).long_leave?
    assert_equal false, klass.new(working_days: 3, blocked: false).long_leave?
    assert_equal true, klass.new(working_days: 12, blocked: false).not_blocked?
    assert_equal true, klass.new(working_days: 12).call_predicate(:blocked, blocked: true)
  end

  def test_strict_raises_when_predicate_raises
    model = build_model(strict: true).new(working_days: 12)
    error = assert_raises(Predicate::EvaluationError) { model.blocked? }
    assert_equal :blocked, error.predicate_name
    assert_kind_of KeyError, error.cause
    assert_raises(Predicate::EvaluationError) { model.call_predicate(:blocked) }
  end

  def test_strict_negation_of_failure_does_not_pass
    model = build_model(strict: true).new(working_days: 12)
    error = assert_raises(Predicate::EvaluationError) { model.not_blocked? }
    assert_equal :blocked, error.predicate_name
  end

  def test_strict_typo_inside_a_predicate_raises
    model = build_model(strict: true).new(working_days: 12)
    error = assert_raises(Predicate::UndefinedPredicate) { model.not_typo? }
    assert_equal :hr_aproved, error.predicate_name
  end

  def test_strict_unknown_predicate_method_is_not_false
    model = build_model(strict: true).new(working_days: 12)
    assert_raises(NoMethodError) { model.no_such_predicate? }
    assert_raises(Predicate::UndefinedPredicate) { model.call_predicate(:no_such_predicate) }
  end

  def test_strict_reaches_section_predicates
    klass = build_model(strict: true)
    assert_equal true, klass.new(working_days: 12).needs_hr?
    assert_equal false, klass.new(working_days: 3).needs_hr?
  end

  def test_non_predicate_methods_still_raise_no_method_error
    model = build_model(strict: true).new(working_days: 12)
    assert_raises(NoMethodError) { model.unknown_method }
  end
end
