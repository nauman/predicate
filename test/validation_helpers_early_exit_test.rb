# frozen_string_literal: true

require_relative 'test_helper'

# validates_numericality_of / validates_length_of used `return false` inside a
# block, which raised LocalJumpError and only read as false because the core
# swallowed it. Strict mode shows whether an error is involved.
class ValidationHelpersEarlyExitTest < Minitest::Test
  def setup
    Predicate.clear_registry!
    @core = Predicate.define(:person, strict: true) do
      validates_numericality_of :age, greater_than: 0
      validates_length_of :password, minimum: 8
      section :extra do
        validates_numericality_of :score, less_than: 10
      end
    end
  end

  def test_non_numeric_is_false_without_an_error
    assert_equal false, @core.call(:valid_age, { age: 'x' })
    assert_equal false, @core.call(:valid_age, {})
    assert_equal true, @core.call(:valid_age, { age: 5 })
    assert_equal false, @core.call(:valid_age, { age: 0 })
  end

  def test_value_without_length_is_false_without_an_error
    assert_equal false, @core.call(:valid_password_length, { password: 5 })
    assert_equal true, @core.call(:valid_password_length, { password: 'longenough' })
    assert_equal false, @core.call(:valid_password_length, { password: 'short' })
  end

  def test_section_helper
    assert_equal false, @core.call_section(:extra, :valid_score, { score: 'x' })
    assert_equal true, @core.call_section(:extra, :valid_score, { score: 3 })
  end
end
