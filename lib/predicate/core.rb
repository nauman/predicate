# frozen_string_literal: true

module Predicate
  # Core Engine
  #
  # The central engine for managing and executing predicates.
  #
  # Features::
  # * Predicate registration and execution
  # * State management
  # * Caching with SHA256 keys
  # * Performance monitoring
  # * Section-based organization
  # * Validation helpers (via Validation module)
  #
  # Usage::
  #   core = Predicate::Core.new(:user)
  #   core.add_predicate(:active) { |s| s[:active] == true }
  #   core.call(:active, { active: true })
  #
  # @author Nauman Tariq
  # @version 1.0.0
  class Core
    include Predicate::Validation

    attr_reader :entity, :predicates, :sections

    # Initialize a new predicate core
    # @param entity [Symbol, String] The entity name
    # @param cache_ttl [Numeric, nil] Cache time-to-live in seconds (nil = no expiration)
    # @param thread_safe [Boolean] Enable thread-safe cache operations (default: false)
    def initialize(entity, cache_ttl: nil, thread_safe: false)
      @entity = entity.to_sym
      @predicates = {}
      @sections = {}
      @memoized_results = {}  # Cache for predicate results
      @cache_timestamps = {}  # Track cache entry creation times (for TTL)
      @cache_ttl = cache_ttl  # nil = no expiration, number = seconds
      @performance_stats = {} # Track performance metrics
      @cache_hits = 0
      @cache_misses = 0
      @cache_size_limit = 1000 # Prevent memory bloat
      @cache_writes = 0        # Track writes for periodic cleanup
      @thread_safe = thread_safe # Enable thread-safe operations
      @cache_mutex = thread_safe ? Mutex.new : nil # Protect cache operations
    end

    # Add a predicate to the core
    # @param name [Symbol, String] The predicate name
    # @param block [Proc] The predicate logic
    # @example
    #   core.add_predicate(:has_media) { |s| is_present?(s[:media_attachment_ids]) }
    def add_predicate(name, &block)
      raise InvalidPredicate, 'Predicate block is required' unless block_given?

      @predicates[name.to_sym] = block
      clear_cache! # Clear cache when predicates change
    end

    # Register a safe declarative predicate.  It uses no Ruby evaluation and
    # is exposed through the same explicit outcome API.
    def add_declarative(name, document)
      Predicate::Declarative.validate!(document)
      add_predicate(name) do |state|
        outcome = Predicate::Declarative.evaluate(document, state)
        raise Predicate::InvalidPredicate, outcome.error if outcome.failed?
        outcome.matched?
      end
    end
    alias add_safe_predicate add_declarative

    def evaluate_declarative(name, state)
      evaluate(name, state)
    end

    # Add section predicates for grouping related predicates
    # @param section_name [Symbol, String] The section name
    # @param block [Proc] Block containing section predicates
    # @example
    #   core.add_section(:media) do |predicates|
    #     predicates[:has_media] = ->(s) { is_present?(s[:media_attachment_ids]) }
    #     predicates[:has_minimum_images] = ->(s) { s[:media_attachment_ids].length >= 1 }
    #   end
    def add_section(section_name, &block)
      raise InvalidPredicate, 'Section block is required' unless block_given?

      @sections[section_name.to_sym] = block
    end

    # Call a predicate with state
    # @param name [Symbol, String] The predicate name
    # @param state [Hash] The state to evaluate against
    # @return [Boolean] The predicate result
    # @example
    #   result = core.call(:has_media, { media_attachment_ids: [1, 2] })
    def call(name, state)
      call_impl(name, state)
    end

    # Explicit evaluation. Unlike #call, this never collapses missing facts,
    # exceptions, or non-boolean results into false.
    def evaluate(name, state)
      predicate = find_predicate(name)
      return Predicate::Outcome.new(:failed, error: "unknown predicate: #{name}") unless predicate

      cache_key = create_cache_key(name, state)
      cached = cache_read(cache_key)
      if cached != :miss
        return Predicate::Outcome.new(cached ? :matched : :not_matched)
      end

      begin
        result = predicate.call(state)
        unless result == true || result == false
          return Predicate::Outcome.new(:failed, error: "predicate #{name} returned #{result.class}, expected true or false")
        end
        cache_write(cache_key, result)
        Predicate::Outcome.new(result ? :matched : :not_matched)
      rescue StandardError => e
        Predicate::Outcome.new(:failed, error: "#{e.class}: #{e.message}")
      end
    end

    # Internal implementation of call (extracted for mutex wrapping)
    # @param name [Symbol, String] The predicate name
    # @param state [Hash] The state to evaluate against
    # @return [Boolean] The predicate result
    def call_impl(name, state)
      start_time = Predicate::Util.now

      # Create optimized cache key from predicate name + state hash
      cache_key = create_cache_key(name, state)

      # Return cached result if available AND still valid (TTL check)
      cached = cache_read(cache_key)
      if cached != :miss
        @cache_hits += 1
        track_performance(name, 0.0)
        Predicate::Performance.track_cache_hit(name) if defined?(Predicate::Performance)
        return cached
      end

      @cache_misses += 1
      Predicate::Performance.track_cache_miss(name) if defined?(Predicate::Performance)

      # Find and execute predicate
      predicate = find_predicate(name)
      return false unless predicate

      begin
        result = predicate.call(state)
        # Preserve the trusted Ruby DSL's historical raw-value behavior.  The
        # explicit #evaluate API rejects raw values.  Nil remains a false result
        # and exceptions are never cached.
        if result.nil?
          track_performance(name, Predicate::Util.now - start_time)
          return false
        end
        cache_write(cache_key, result)

        track_performance(name, Predicate::Util.now - start_time)
        result
      rescue StandardError => e
        track_performance(name, Predicate::Util.now - start_time)

        # Log error but don't raise - predicates should be resilient
        Rails.logger.error "Predicate #{name} failed: #{e.message}" if defined?(Rails) && Rails.respond_to?(:logger)
        false
      end
    end

    # Call a section predicate
    # @param section_name [Symbol, String] The section name
    # @param predicate_name [Symbol, String] The predicate name within the section
    # @param state [Hash] The state to evaluate against
    # @return [Boolean] The predicate result
    # @example
    #   result = core.call_section(:media, :has_media, { media_attachment_ids: [1, 2] })
    def call_section(section_name, predicate_name, state)
      call_section_impl(section_name, predicate_name, state)
    end

    # Internal implementation of call_section (extracted for mutex wrapping)
    # @param section_name [Symbol, String] The section name
    # @param predicate_name [Symbol, String] The predicate name within the section
    # @param state [Hash] The state to evaluate against
    # @return [Boolean] The predicate result
    def call_section_impl(section_name, predicate_name, state)
      start_time = Predicate::Util.now

      # Use deterministic cache key (same as regular predicates)
      combined_name = "#{section_name}_#{predicate_name}"
      cache_key = create_cache_key(combined_name, state)

      # Check cache with hit/miss tracking (same as regular predicates)
      # Also check TTL validity
      cached = cache_read(cache_key)
      if cached != :miss
        @cache_hits += 1
        track_performance(combined_name.to_sym, 0.0)
        return cached
      end

      @cache_misses += 1  # Track cache miss

      # Execute section block to get predicates
      section_predicates = {}
      section = @sections[section_name.to_sym]
      return false unless section

      section.call(section_predicates)

      predicate = section_predicates[predicate_name.to_sym]
      return false unless predicate

      begin
        result = predicate.call(state)
        if result.nil?
          duration = Predicate::Util.now - start_time
          track_performance(combined_name.to_sym, duration)
          return false
        end
        cache_write(cache_key, result)

        duration = Predicate::Util.now - start_time
        track_performance(combined_name.to_sym, duration)
        result
      rescue StandardError => e
        duration = Predicate::Util.now - start_time
        track_performance(combined_name.to_sym, duration)

        # Log error but don't raise - predicates should be resilient
        if defined?(Rails) && Rails.respond_to?(:logger)
          Rails.logger.error "Section predicate #{combined_name} failed: #{e.message}"
        end
        false
      end
    end

    # Check if a predicate exists
    # @param name [Symbol, String] The predicate name
    # @return [Boolean] True if predicate exists
    def predicate?(name)
      @predicates.key?(name.to_sym)
    end

    # Check if a section exists
    # @param name [Symbol, String] The section name
    # @return [Boolean] True if section exists
    def has_section?(name)
      @sections.key?(name.to_sym)
    end

    # Get all predicate names
    # @return [Array<Symbol>] Array of predicate names
    def predicate_names
      @predicates.keys
    end

    # Get all section names
    # @return [Array<Symbol>] Array of section names
    def section_names
      @sections.keys
    end

    # Clear the cache
    def clear_cache!
      if @thread_safe
        @cache_mutex.synchronize do
          @memoized_results.clear
          @cache_timestamps.clear if @cache_ttl
        end
      else
        @memoized_results.clear
        @cache_timestamps.clear if @cache_ttl
      end
    end

    # Get cache statistics
    # @return [Hash] Cache statistics
    def cache_stats
      {
        cached_results: @memoized_results.size,
        predicates: @predicates.size,
        sections: @sections.size,
        cache_hits: @cache_hits,
        cache_misses: @cache_misses,
        cache_hit_ratio: calculate_cache_hit_ratio
      }
    end

    # Get performance statistics
    # @return [Hash] Performance statistics
    def performance_stats
      @performance_stats.dup
    end

    private

    def cache_read(cache_key)
      operation = lambda do
        if @memoized_results.key?(cache_key) && cache_valid?(cache_key)
          @memoized_results[cache_key]
        else
          :miss
        end
      end
      @thread_safe ? @cache_mutex.synchronize(&operation) : operation.call
    end

    def cache_write(cache_key, result)
      operation = lambda { store_in_cache(cache_key, result) }
      @thread_safe ? @cache_mutex.synchronize(&operation) : operation.call
    end

    # Create an optimized cache key from predicate name and state
    # @param name [Symbol, String] The predicate name
    # @param state [Hash] The state hash
    # @return [String] The cache key
    def create_cache_key(name, state)
      # Use deterministic JSON serialization + SHA256 for collision-free keys
      # Sort keys for consistency regardless of hash order

      require 'json'
      require 'digest'

      sorted_state = state.sort_by { |k, _v| k.to_s }.to_h
      state_json = JSON.generate(sorted_state)
      # Use first 16 chars of SHA256 hash for shorter keys
      state_hash = Digest::SHA256.hexdigest(state_json)[0..15]

      "#{name}_#{state_hash}"
    rescue StandardError => e
      # Fallback to original hash method if JSON fails (for non-serializable objects)
      Rails.logger.warn "Cache key generation fallback: #{e.message}" if defined?(Rails) && Rails.respond_to?(:logger)
      state_signature = state.sort_by { |k, _v| k.to_s }.hash
      "#{name}_#{state_signature}"
    end

    # Store result in cache with size management
    # @param cache_key [String] The cache key
    # @param result [Boolean] The result to cache
    def store_in_cache(cache_key, result)
      # Implement LRU-style cache management
      if @memoized_results.size >= @cache_size_limit
        # Remove oldest 25% of entries when cache is full
        entries_to_remove = @cache_size_limit / 4
        @memoized_results.keys.first(entries_to_remove).each do |key|
          @memoized_results.delete(key)
          @cache_timestamps.delete(key) # Also remove timestamp
        end
      end

      @memoized_results[cache_key] = result
      # Track creation time if TTL enabled
      @cache_timestamps[cache_key] = Predicate::Util.now if @cache_ttl

      # Periodic cleanup of expired entries (every 100 writes)
      @cache_writes += 1
      clean_expired_cache! if @cache_ttl && (@cache_writes % 100).zero?
    end

    # Check if a cache entry is still valid (TTL check)
    # @param cache_key [String] The cache key to check
    # @return [Boolean] True if cache entry is valid (not expired)
    def cache_valid?(cache_key)
      # If no TTL configured, cache is always valid
      return true unless @cache_ttl

      # If no timestamp tracked, consider invalid (shouldn't happen, but defensive)
      return false unless @cache_timestamps.key?(cache_key)

      # Check if entry age is within TTL
      entry_age = Predicate::Util.now - @cache_timestamps[cache_key]
      entry_age <= @cache_ttl
    end

    # Clean up expired cache entries
    # Called periodically (every 100 writes) when TTL is enabled
    def clean_expired_cache!
      return unless @cache_ttl

      current_time = Predicate::Util.now
      expired_keys = []

      # Find all expired entries
      @cache_timestamps.each do |key, timestamp|
        entry_age = current_time - timestamp
        expired_keys << key if entry_age > @cache_ttl
      end

      # Remove expired entries
      expired_keys.each do |key|
        @memoized_results.delete(key)
        @cache_timestamps.delete(key)
      end
    end

    # Calculate cache hit ratio
    # @return [Float] Hit ratio between 0.0 and 1.0
    def calculate_cache_hit_ratio
      total = @cache_hits + @cache_misses
      return 0.0 if total.zero?

      (@cache_hits.to_f / total).round(3)
    end

    # Find a predicate by name (checks both direct predicates and sections)
    # @param name [Symbol, String] The predicate name
    # @return [Proc, nil] The predicate proc or nil if not found
    def find_predicate(name)
      # First check direct predicates
      return @predicates[name.to_sym] if @predicates.key?(name.to_sym)

      # Then check sections
      @sections.each_value do |section_block|
        section_predicates = {}
        section_block.call(section_predicates)
        return section_predicates[name.to_sym] if section_predicates.key?(name.to_sym)
      end

      nil
    end

    # Track performance metrics for a predicate
    # @param predicate_name [Symbol, String] The predicate name
    # @param duration [Float] Execution time in seconds
    def track_performance(predicate_name, duration)
      # Track stats unconditionally (not just when Rails is defined)
      @performance_stats[predicate_name.to_sym] ||= {
        calls: 0,
        total_time: 0.0,
        average_time: 0.0,
        min_time: Float::INFINITY,
        max_time: 0.0
      }

      stats = @performance_stats[predicate_name.to_sym]
      stats[:calls] += 1
      stats[:total_time] += duration
      stats[:average_time] = stats[:total_time] / stats[:calls]
      stats[:min_time] = [stats[:min_time], duration].min
      stats[:max_time] = [stats[:max_time], duration].max

      # Optional: Log to Rails if available
      if defined?(Rails) && Rails.respond_to?(:logger)
        Rails.logger.debug { "Predicate #{predicate_name} executed in #{duration}s" }
      end

      # Track globally if Performance module is available
      Predicate::Performance.track(predicate_name, duration) if defined?(Predicate::Performance)
    end
  end
end
