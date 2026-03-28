# ActiveWindows — Review & Improvement Plan

## Overall Assessment

The gem provides a fluent DSL for SQL window functions in ActiveRecord. Core functionality is implemented and tested, with 16 window functions available via both fluent and hash APIs. 53 tests passing with 242 assertions.

---

## Completed

- ~~**WindowChain disconnected from window()**~~ — Fixed. WindowChain holds a relation reference and delegates query methods through `to_relation`.
- ~~**Relation state not preserved through cloning**~~ — Fixed. Uses ActiveRecord's `select()` infrastructure instead of custom `@window_values`, so state survives `spawn`/`clone`/chaining.
- ~~**Window frame hardcoded**~~ — Fixed. `apply_window_frame` now passes user-provided string to Arel.
- ~~**SQL injection via Arel.sql()**~~ — Mitigated. Column references now use `klass.arel_table[column]` instead of raw `Arel.sql()`.
- ~~**Broken test suite**~~ — Fixed. Placeholder test removed, 53 real tests passing.
- ~~**Bundler constraint**~~ — Fixed. Changed `~> 2.0` to `>= 2.0`.
- ~~**Standalone arel gem conflict**~~ — Fixed. Removed incompatible `arel >= 9.0` dependency (ActiveRecord 8 bundles its own).
- ~~**sqlite3 version**~~ — Fixed. Updated to `>= 2.1` for ActiveRecord 8 compatibility.
- ~~**Only row_number supported**~~ — Fixed. Added 15 more window functions: `rank`, `dense_rank`, `percent_rank`, `cume_dist`, `ntile`, `lag`, `lead`, `first_value`, `last_value`, `nth_value`, `window_sum`, `window_avg`, `window_count`, `window_min`, `window_max`.
- ~~**Empty partition/order arrays**~~ — Fixed. Guarded with early return.
- ~~**No real tests**~~ — Fixed. 53 Minitest tests with SQL verification and query execution against SQLite.
- ~~**Gemspec TODO placeholders**~~ — Fixed. Summary, description, homepage, source/changelog URIs all filled in.
- ~~**README boilerplate**~~ — Fixed. Full documentation with usage examples, API reference, and generated SQL.
- ~~**CI only Ruby 3.3.5**~~ — Fixed. Matrix now tests Ruby 3.3, 3.4, and 4.0.
- ~~**RSpec dependency**~~ — Removed. Tests rewritten to Minitest.
- ~~**RuboCop dependency**~~ — Removed.
- ~~**LICENSE**~~ — Cleaned up. Full name, no year, `.txt` extension removed.
- ~~**Boilerplate files**~~ — Removed. `CHANGELOG.md`, `CODE_OF_CONDUCT.md`, `bin/console`, `bin/setup`, `sig/active_windows.rbs`.
- ~~**Ordering direction**~~ — Fixed. Supports `order(salary: :desc)`, `order({ col: :asc }, { col: :desc })`, and hash API `order: { salary: :desc }`.
- ~~**Gemfile/gemspec duplication**~~ — Fixed. Dev gems (`minitest`, `rake`) defined only in Gemfile under `test, development` group. No more bundler override warnings.
- ~~**Cross-platform lockfile**~~ — Fixed. Added `aarch64-linux`, `arm-linux`, `arm64-darwin`, `x86_64-darwin`, `x86_64-linux` platforms.

---

## Remaining Work

### Medium Priority

1. **Edge case tests** — Not yet covered:
   - Empty result sets, single-row partitions
   - NULL values in partition/order columns
   - Multiple window functions in one query
   - Complex chaining with `.joins()`, `.group()`, `.includes()`

2. **Multiple window functions in one call** — The hash API supports it (`User.window(row_number: {...}, rank: {...})`), but this is not tested.

### Low Priority

3. **RBS type signatures** — Add method signatures for `QueryMethods` and `WindowChain`.

4. **GitHub Actions for gem publishing** — No automated release workflow.

5. **PostgreSQL test coverage** — SQLite has limited window function support. Testing against PostgreSQL would catch more issues.

6. **Input validation on function arguments** — `lag`, `lead`, `ntile`, `nth_value` accept arbitrary values without type checking (e.g., `ntile("abc")` won't raise until query execution).
