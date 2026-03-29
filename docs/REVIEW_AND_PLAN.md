# ActiveWindows — Review & Improvement Plan

## Overall Assessment

The gem provides a fluent DSL for SQL window functions in ActiveRecord. Core functionality is implemented and tested, with 16 window functions available via fluent, `window(:symbol)`, and hash APIs. 82 tests passing with 399 assertions. CI runs against SQLite, PostgreSQL, and MySQL.

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
- ~~**Ordering direction**~~ — Fixed. Supports `order_by(salary: :desc)`, `order_by({ col: :asc }, { col: :desc })`, and hash API `order_by: { salary: :desc }`.
- ~~**Gemfile/gemspec duplication**~~ — Fixed. Dev gems (`minitest`, `rake`) defined only in Gemfile under `test, development` group. No more bundler override warnings.
- ~~**Cross-platform lockfile**~~ — Fixed. Added `aarch64-linux`, `arm-linux`, `arm64-darwin`, `x86_64-darwin`, `x86_64-linux` platforms.
- ~~**Multiple window functions in one call**~~ — Tested. Single `window()` with multiple keys and chaining separate `window()` calls both work.
- ~~**Edge case tests**~~ — Added. Empty result sets, single-row partitions, NULL values in partition/order/value columns, chaining with `.joins()`, `.includes()`, `.where()` + `.joins()`. 67 tests, 328 assertions.
- ~~**PostgreSQL CI**~~ — Added. GitHub Actions workflow tests against PostgreSQL 17 with service container.
- ~~**MySQL CI**~~ — Added. GitHub Actions workflow tests against MySQL 8.0 with service container.
- ~~**MySQL compatibility**~~ — Fixed. Aliases now use `klass.connection.quote_column_name` to properly quote reserved words (e.g., `rank`) with backticks on MySQL and double quotes on PostgreSQL/SQLite. Test assertions use adapter-agnostic `q()` and `col()` helpers.
- ~~**WindowChain `order` naming collision**~~ — Fixed. Renamed to `order_by` to avoid conflict with ActiveRecord's `.order()`. Both fluent (`.order_by(:salary)`) and hash (`order_by: :salary`) APIs use `order_by`. WindowChain delegates `.order()` to the relation for query-level ordering. Uses `method_missing` for full relation method coverage.
- ~~**Association name resolution**~~ — Added. `belongs_to`: `partition_by(:user)` resolves to `user_id`. Works in both fluent and hash APIs.
- ~~**Unified `window()` entry point**~~ — Added. `window(:row_number)` returns a WindowChain (fluent), `window(:lag, :salary, 1, 0)` passes function args, `window(row_number: { ... })` is hash API. Single method, three modes.
- ~~**Named windows**~~ — Added. `define: { w: { partition_by: :department, order_by: :salary } }` with `over: :w` references. Multiple definitions supported. Function-level options merge with the definition.
- ~~**Frame clause is raw SQL**~~ — Fixed. Hash DSL for frames: `frame: { rows: [:unbounded_preceding, :current_row] }`. Supports `:rows`/`:range`, integer offsets, and all standard bounds. Raw SQL strings still accepted as fallback. 93 tests, 429 assertions.

---

## Remaining Work

### Low Priority

1. **RBS type signatures** — Add method signatures for `QueryMethods` and `WindowChain`.

2. **GitHub Actions for gem publishing** — No automated release workflow.

3. **Input validation on function arguments** — `lag`, `lead`, `ntile`, `nth_value` accept arbitrary values without type checking (e.g., `ntile("abc")` won't raise until query execution).
