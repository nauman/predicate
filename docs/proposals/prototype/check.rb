require 'json'
require_relative 'evaluator'

fixtures = JSON.parse(File.read(File.join(__dir__, '../predicate-v1.fixtures.json')))
backend = ARGV.include?('--json-logic') ? (require_relative 'json_logic_backend'; PredicateJsonLogic) : PredicatePrototype
checks = 0
[fixtures, *fixtures.fetch('scenarios')].each do |scenario|
  rule = scenario.fetch('rule')
  raise "Invalid fixture rule #{rule['id']}" unless PredicatePrototype.valid?(rule)
  scenario.fetch('evaluations').each do |row|
    actual = backend.evaluate(rule, row.fetch('facts'))
    raise "#{rule['id']} #{row}: got #{actual}" unless actual == row.fetch('status')
    checks += 1
  end
end

(fixtures.fetch('invalid_documents') + fixtures.fetch('invalid_rules')).each do |row|
  raise row.fetch('why') if PredicatePrototype.valid?(row.fetch('document'))
  raise row.fetch('why') unless backend.evaluate(row.fetch('document'), {}) == 'failed'
  checks += 1
end
[Float::NAN, Float::INFINITY, -Float::INFINITY, Complex(1, 2), Rational(3, 2)].each do |value|
  raise value.inspect unless backend.evaluate(fixtures.fetch('rule'), { 'working_days' => value }) == 'failed'
end
puts "#{checks} Ruby cases passed"
