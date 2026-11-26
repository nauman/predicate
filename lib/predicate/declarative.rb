# frozen_string_literal: true

require 'json'

module Predicate
  # Explicit result of an evaluation.  Raw Ruby values and exceptions are never
  # exposed as implicit boolean false values.
  class Outcome
    STATUSES = %i[matched not_matched failed].freeze

    attr_reader :status, :error

    def initialize(status, error: nil)
      raise ArgumentError, "invalid outcome: #{status}" unless STATUSES.include?(status)

      @status = status
      @error = error
    end

    def ==(other)
      other.is_a?(Outcome) ? status == other.status : status == other
    end

    def matched? = status == :matched
    def not_matched? = status == :not_matched
    def failed? = status == :failed

    def [](key)
      case key.to_sym
      when :status then status
      when :error then error
      else nil
      end
    end

    def to_h
      { status: status }.tap { |h| h[:error] = error if error }
    end
  end

  # Safe, versioned declarative predicate language.
  #
  # The implementation deliberately contains no Ruby eval/stringification or
  # application callbacks.  Facts are supplied by the host and are allowlisted
  # in the document.
  module Declarative
    SCHEMA_VERSION = 'predicate/v1'
    DEFAULT_MAX_NODES = 64
    DEFAULT_MAX_DEPTH = 16
    OPERATORS = %w[
      and all or any not eq ne gt gte lt lte in present missing
    ].freeze

    module_function

    def schema
      {
        '$schema' => 'predicate/declarative-json-schema/v1',
        'version' => SCHEMA_VERSION,
        'closed' => true,
        'operators' => OPERATORS
      }
    end

    def validate(document)
      errors = []
      begin
        doc = normalize_document(document)
      rescue ArgumentError, TypeError => e
        return { valid: false, errors: [e.message] }
      end

      version = doc['version'] || doc['schema']
      unless [SCHEMA_VERSION, '1', 1].include?(version)
        errors << "unsupported schema version: #{version.inspect}"
      end

      unknown_document_keys = doc.keys - %w[version schema facts fact_types condition rule expression predicate max_nodes max_depth name]
      errors.concat(unknown_document_keys.map { |key| "unknown document key: #{key}" })

      facts = doc['facts']
      if facts.nil?
        errors << 'missing facts allowlist'
      elsif !facts.is_a?(Hash) && !facts.is_a?(Array)
        errors << 'facts must be an object or array'
      end

      fact_types = doc['fact_types']
      if fact_types
        unless fact_types.is_a?(Hash)
          errors << 'fact_types must be an object'
        else
          fact_types.each do |name, type|
            unless valid_fact_name?(name, facts)
              errors << "fact_types names unknown fact: #{name}"
            end
            unless %w[boolean integer number string array object].include?(type.to_s)
              errors << "unsupported fact type for #{name}: #{type.inspect}"
            end
          end
        end
      end

      max_nodes = doc.fetch('max_nodes', DEFAULT_MAX_NODES)
      max_depth = doc.fetch('max_depth', DEFAULT_MAX_DEPTH)
      unless max_nodes.is_a?(Integer) && max_nodes.between?(1, DEFAULT_MAX_NODES)
        errors << "max_nodes must be between 1 and #{DEFAULT_MAX_NODES}"
      end
      unless max_depth.is_a?(Integer) && max_depth.between?(1, DEFAULT_MAX_DEPTH)
        errors << "max_depth must be between 1 and #{DEFAULT_MAX_DEPTH}"
      end

      root = doc['condition'] || doc['rule'] || doc['expression'] || doc['predicate']
      unless root
        errors << 'missing condition'
      else
        validate_node(root, facts, max_nodes, max_depth, 0, 0, errors)
      end

      { valid: errors.empty?, errors: errors }
    end

    def validate!(document)
      result = validate(document)
      raise Predicate::InvalidPredicate, result[:errors].join('; ') unless result[:valid]

      true
    end

    def valid?(document)
      validate(document)[:valid]
    end

    def evaluate(document, facts)
      validation = validate(document)
      return Outcome.new(:failed, error: validation[:errors].join('; ')) unless validation[:valid]

      doc = normalize_document(document)
      root = doc['condition'] || doc['rule'] || doc['expression'] || doc['predicate']
      fact_types = doc['fact_types']
      if fact_types.nil? && doc['facts'].is_a?(Hash)
        fact_types = doc['facts']
      end
      evaluate_node(root, facts, fact_types || {})
    rescue StandardError => e
      Outcome.new(:failed, error: e.message)
    end

    def simulate(document, facts)
      evaluate(document, facts)
    end

    def normalize_document(document)
      case document
      when Hash
        doc = document
      when String
        doc = JSON.parse(document)
      else
        raise ArgumentError, 'declarative predicate must be a Hash or JSON string'
      end
      raise ArgumentError, 'declarative predicate must be a JSON object' unless doc.is_a?(Hash)

      normalized = {}
      doc.each { |key, value| normalized[key.to_s] = value }
      normalized
    end
    private_class_method :normalize_document

    def validate_node(node, facts, max_nodes, max_depth, nodes, depth, errors)
      nodes += 1
      return nodes if nodes > max_nodes
      return nodes if depth > max_depth
      unless node.is_a?(Hash)
        errors << 'condition nodes must be objects'
        return nodes
      end

      keys = node.keys.map(&:to_s)
      op = node['op'] || node[:op] || node['operator'] || node[:operator]
      op = op.to_s if op
      unless OPERATORS.include?(op)
        errors << "unknown or missing operator: #{op.inspect}"
        return nodes
      end

      allowed = allowed_keys(op)
      unknown = keys.reject { |key| allowed.include?(key) }
      errors.concat(unknown.map { |key| "unknown key for #{op}: #{key}" }) unless unknown.empty?

      if %w[and all or any].include?(op)
        children = node['children'] || node['args'] || node['conditions']
        unless children.is_a?(Array) && !children.empty?
          errors << "#{op} requires a non-empty children/args array"
        else
          children.each { |child| nodes = validate_node(child, facts, max_nodes, max_depth, nodes, depth + 1, errors) }
        end
      elsif op == 'not'
        child = node['condition'] || node['operand'] || node['child']
        unless child
          errors << 'not requires condition/operand'
        else
          nodes = validate_node(child, facts, max_nodes, max_depth, nodes, depth + 1, errors)
        end
      else
        fact = node['fact'] || node['field']
        unless valid_fact_name?(fact, facts)
          errors << "unknown or missing fact: #{fact.inspect}"
        end
        if %w[in].include?(op) && !node['values'].is_a?(Array)
          errors << 'in requires a values array'
        elsif %w[present missing].include?(op)
          # No value required.
        elsif node['value'].nil?
          errors << "#{op} requires a value"
        end
      end
      nodes
    end
    private_class_method :validate_node

    def allowed_keys(op)
      common = %w[op operator fact field]
      return %w[op operator children args conditions] if %w[and all or any].include?(op)
      return %w[op operator condition operand child] if op == 'not'
      return common + %w[values] if op == 'in'
      return common if %w[present missing].include?(op)

      common + %w[value]
    end
    private_class_method :allowed_keys

    def valid_fact_name?(fact, facts)
      return false unless fact.is_a?(String) || fact.is_a?(Symbol)
      name = fact.to_s
      return facts.key?(name) || facts.key?(name.to_sym) if facts.is_a?(Hash)
      if facts.is_a?(Array)
        return true if facts.include?(name) || facts.include?(name.to_sym)
        return facts.any? do |entry|
          entry.is_a?(Hash) &&
            ((entry['name'] || entry['fact'] || entry[:name] || entry[:fact]).to_s == name)
        end
      end

      false
    end
    private_class_method :valid_fact_name?

    def evaluate_node(node, facts, fact_types)
      begin
        op = (node['op'] || node[:op] || node['operator'] || node[:operator]).to_s
        case op
        when 'and', 'all'
          children = node['children'] || node['args'] || node['conditions']
          children.each do |child|
            result = evaluate_node(child, facts, fact_types)
            return result if result.failed?
            return Outcome.new(:not_matched) if result.not_matched?
          end
          Outcome.new(:matched)
        when 'or', 'any'
          children = node['children'] || node['args'] || node['conditions']
          children.each do |child|
            result = evaluate_node(child, facts, fact_types)
            return result if result.failed?
            return Outcome.new(:matched) if result.matched?
          end
          Outcome.new(:not_matched)
        when 'not'
          child = node['condition'] || node['operand'] || node['child']
          result = evaluate_node(child, facts, fact_types)
          return result if result.failed?
          Outcome.new(result.matched? ? :not_matched : :matched)
        else
          fact_name = (node['fact'] || node['field']).to_s
          found = facts.respond_to?(:key?) &&
                  (facts.key?(fact_name) || facts.key?(fact_name.to_sym))
          return Outcome.new(:failed, error: "missing fact: #{fact_name}") unless found

          raw = facts.key?(fact_name) ? facts[fact_name] : facts[fact_name.to_sym]
          return Outcome.new(:failed, error: "missing fact: #{fact_name}") if raw.nil?

          declared_type = fact_types[fact_name] || fact_types[fact_name.to_sym]
          if declared_type
            type_error = fact_type_error(raw, declared_type)
            return Outcome.new(:failed, error: "invalid fact type for #{fact_name}: #{type_error}") if type_error
          end

          matched =
            case op
            when 'eq' then raw == node['value']
            when 'ne' then raw != node['value']
            when 'gt' then comparable(raw) { raw > node['value'] }
            when 'gte' then comparable(raw) { raw >= node['value'] }
            when 'lt' then comparable(raw) { raw < node['value'] }
            when 'lte' then comparable(raw) { raw <= node['value'] }
            when 'in' then node['values'].include?(raw)
            when 'present' then !raw.nil?
            when 'missing' then raw.nil?
            else false
            end
          Outcome.new(matched ? :matched : :not_matched)
        end
      rescue StandardError => e
        Outcome.new(:failed, error: e.message)
      end
    end
    private_class_method :evaluate_node

    def fact_type_error(raw, declared_type)
      valid =
        case declared_type.to_s
        when 'boolean' then raw == true || raw == false
        when 'integer' then raw.is_a?(Integer)
        when 'number' then raw.is_a?(Numeric)
        when 'string' then raw.is_a?(String)
        when 'array' then raw.is_a?(Array)
        when 'object' then raw.is_a?(Hash)
        else
          false
        end
      valid ? nil : "expected #{declared_type}"
    end
    private_class_method :fact_type_error

    def comparable(_raw)
      yield
    rescue StandardError => e
      raise ArgumentError, "comparison failed: #{e.message}"
    end
    private_class_method :comparable
  end
end
