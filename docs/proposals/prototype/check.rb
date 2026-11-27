require 'json'
require_relative 'evaluator'

fixtures = JSON.parse(File.read(File.join(__dir__, '../predicate-v1.fixtures.json')))
checks = 0
[fixtures, *fixtures.fetch('scenarios')].each do |scenario|
  rule = scenario.fetch('rule')
  raise "Invalid fixture rule #{rule['id']}" unless PredicatePrototype.valid?(rule)
  scenario.fetch('evaluations').each do |row|
    actual = PredicatePrototype.evaluate(rule, row.fetch('facts'))
    raise "#{rule['id']} #{row}: got #{actual}" unless actual == row.fetch('status')
    checks += 1
  end
end

(fixtures.fetch('invalid_documents') + fixtures.fetch('invalid_rules')).each do |row|
  raise row.fetch('why') if PredicatePrototype.valid?(row.fetch('document'))
  checks += 1
end
puts "#{checks} Ruby cases passed"
