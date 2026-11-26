# Changelog

All notable changes to this project will be documented in this file. The release
workflow refuses to publish a version with no entry — see RELEASING.md.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-11-26

Versions 1.2.1 and 1.2.2 were never published; their changes ship here.

### Added
- Opt-in strict mode: `Predicate.define(:leave, strict: true)` (or
  `Predicate::Core.new(:leave, strict: true)`). A predicate that raises now
  raises `Predicate::EvaluationError` (original error as `cause`,
  `predicate_name` set), and calling a predicate or section that is not defined
  raises `Predicate::UndefinedPredicate`. Combinators pass these through, so
  `not_predicate(:blocked)` and `none_of(:blocked)` no longer come out `true`
  when `:blocked` crashed or is a typo. The default is unchanged: failures and
  undefined predicates still read as `false`.
  Through `Predicate::ModelIntegration`, `model.blocked?` raises the same
  errors, reaches predicates defined inside a section, and a `?` method the
  core does not know raises `NoMethodError` instead of returning `false`.

### Changed
- Section results are cached under their own namespace, so section
  `:group`/`:ready` and a direct predicate `:group_ready` no longer share an
  entry. Cache keys for section predicates therefore differ from 1.2.0; the
  cache is in-memory only, so nothing persisted is affected.
- `add_section` clears the cache, so replacing a section no longer serves the
  old section's results.
- Pointed gem metadata and release configuration at the maintainer's personal
  accounts.

### Fixed
- `thread_safe: true` no longer raises `ThreadError` (reported as `false`) when a
  predicate calls another predicate on the same core; the cache lock is now
  re-entrant for the thread holding it.
- A predicate that raises is no longer cached as `false`; the next call
  evaluates it again.
- `validates_numericality_of` and `validates_length_of` returned `false` for a
  non-numeric value or one without a length only because a `LocalJumpError`
  was swallowed, logging "unexpected return" on every such call under Rails.
  They now return `false` directly. Results are unchanged.

## [1.2.0] - 2026-02-24

First public release on RubyGems, as `predicate-rb` (the name `predicate`
belongs to an unrelated gem). `require "predicate"` and the `Predicate`
constant are unchanged; `lib/predicate-rb.rb` only requires `predicate`, so
`Bundler.require` works with `gem "predicate-rb"`.

### Changed
- **Breaking:** the validation helpers `present?(value)` and `blank?(value)` are
  renamed `is_present?(value)` and `is_blank?(value)`. Under Rails, Active
  Support defines zero-argument `Object#present?`/`#blank?`, which Ruby found
  before `method_missing`; the call raised `ArgumentError` and the predicate
  silently returned `false`.
- Including `Predicate::ModelIntegration` loads the model's predicate file by
  naming convention; models no longer call `load_predicates!` explicitly.

### Fixed
- `method_missing` lazy-loads definitions, so a predicate called before its file
  was loaded no longer reports as undefined.

## [1.1.0] - 2026-02-09

### Fixed
- Rails: predicate definition files are ignored by Zeitwerk instead of being
  added to `autoload_paths`, so they register without having to define a
  constant matching their filename.

## [1.0.0] - 2026-01-28

### Added
- Initial release as standalone gem
- Pure boolean predicate DSL with method_missing syntax
- Automatic memoization with SHA256-based cache keys
- TTL (time-to-live) cache expiration support
- Thread-safe operations via optional Mutex
- LRU cache eviction (1000 entry limit)
- Logical combinators: `all_of`, `any_of`, `none_of`, `not_predicate`
- Conditional combinators: `when_present`, `when_blank`
- Section-based predicate grouping
- Rails model integration via `Predicate::ModelIntegration`
- Railtie for automatic Rails integration
- Performance monitoring and statistics
- 27 English-like validation helpers
- Rails validation pattern generators
- Predicate file generator for models
- Comprehensive test suite (183 runs, 508 assertions)

### Changed
- Extracted from StockLive codebase into standalone gem
- Fixed Zeitwerk compatibility (proper gem directory structure)
- Removed Rails-specific Rubocop directives for broader compatibility

### Fixed
- Cache collision issues with SHA256-based keys
- Section predicate caching consistency
- Thread-safety for concurrent environments
