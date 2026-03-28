# ActiveWindows — Deep Review & Improvement Plan

## Overall Assessment

The gem is at an early prototype stage (v0.1.0). The core idea — a fluent DSL for SQL window functions in ActiveRecord — is solid, but there are significant issues across code correctness, tests, documentation, and gem metadata.

---

## Critical Issues

### 1. Broken test suite
`spec/active_windows_spec.rb` has a placeholder `expect(false).to eq(true)` — CI will always fail.

### 2. `WindowChain` is disconnected from `window()`
`row_number()` returns a `WindowChain` with `.as()`, `.partition_by()`, `.order()` methods, but there's no mechanism to actually apply that chain to the relation's SELECT. The fluent API and the hash-based `window()` API are two separate, unconnected interfaces.

### 3. Relation state not preserved through cloning
`@window_values` is a plain instance variable. ActiveRecord's `spawn`/`clone`/`merge` won't carry it forward, so chaining like `User.where(...).window(...)` may silently lose the window definitions.

### 4. Window frame is hardcoded
`apply_window_frame()` ignores its `frame_options` parameter and always emits `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`, making the `:frame` option a no-op.

### 5. SQL injection risk
`Arel.sql()` is used on user-supplied strings without sanitization. If column names come from user input, this is exploitable.

---

## Major Issues

| Area | Issue |
|------|-------|
| **Tests** | Only 2 real tests (method existence + smoke). No tests for SQL output, query execution, partitioning, ordering, aliases, error cases, or chaining. |
| **Gemspec** | Summary, description, homepage, source URI, changelog URI are all `TODO` placeholders — gem can't be published. |
| **README** | Entirely boilerplate template. No usage examples or feature description. |
| **Bundler constraint** | `bundler ~> 2.0` in gemspec conflicts with Bundler 4.x environments. |
| **RBS types** | `sig/active_windows.rbs` only declares `VERSION`. No type signatures for the DSL. |

---

## Moderate Issues

- No support beyond `row_number` — common window functions like `rank`, `dense_rank`, `ntile`, `lag`, `lead`, `sum`, `avg` are missing as first-class DSL methods.
- Empty partition/order arrays could generate invalid SQL (`PARTITION BY ()`) with no guard.
- No tests with actual DB queries — the SQLite setup exists but isn't exercised to verify results.
- CI matrix only tests Ruby 3.3.5 — no multi-version or multi-DB coverage.

---

## What's Good

- Clean Railtie integration pattern
- Arel-based SQL generation (correct approach)
- Fluent interface design is ergonomic
- Test infrastructure (RSpec + SQLite in-memory) is set up and ready
- Frozen string literals, RuboCop configured

---

## Improvement Plan (Priority Order)

### Phase 1 — Fix Critical Bugs

1. **Fix the `WindowChain` to relation integration**
   - The chain needs to actually modify the relation's SELECT projections
   - `WindowChain` should hold a reference to the relation and apply changes when the query is executed

2. **Integrate `@window_values` with ActiveRecord's `spawn`**
   - Hook into the relation's value methods (similar to how `select_values`, `order_values` work)
   - Ensure window definitions survive cloning, merging, and chaining

3. **Implement frame option properly** or remove it from `VALID_WINDOW_OPTIONS`
   - Parse user-provided frame specs (ROWS, RANGE, GROUPS with BETWEEN ... AND ...)
   - Or remove `:frame` until it's properly implemented

4. **Sanitize inputs**
   - Validate column names against the model's columns instead of passing raw strings to `Arel.sql()`
   - Reject or escape anything that doesn't match a known column or safe expression

5. **Fix broken test** (`expect(false).to eq(true)`) and bundler version constraint (`~> 2.0` -> `>= 2.0`)

### Phase 2 — Expand Window Function Support

6. **Add more window functions as first-class DSL methods**
   - `rank` / `dense_rank` / `percent_rank`
   - `ntile(n)`
   - `lag(column, offset, default)` / `lead(column, offset, default)`
   - `first_value` / `last_value` / `nth_value`
   - Aggregate window functions: `sum`, `avg`, `count`, `min`, `max`

7. **Guard against empty partition/order arrays**
   - Skip PARTITION BY / ORDER BY clause when array is empty rather than generating invalid SQL

### Phase 3 — Comprehensive Test Coverage

8. **SQL output verification tests**
   - Assert exact SQL strings or Arel node structures for each DSL combination
   - Cover: single partition, multiple partitions, ordering ASC/DESC, aliases, frames

9. **Query execution tests with seed data**
   - Insert test records, run window function queries, verify actual result values
   - Test with SQLite (and optionally PostgreSQL for full window function support)

10. **Error case tests**
    - Invalid column names, nil arguments, unsupported options
    - Chaining with `.where()`, `.joins()`, `.group()`, `.includes()`

11. **Edge case tests**
    - Empty result sets, single-row partitions, NULL values in partition/order columns
    - Multiple window functions in one query

### Phase 4 — Documentation & Gem Metadata

12. **Complete gemspec metadata**
    - Summary, description, homepage, source code URI, changelog URI

13. **Write README with real usage examples**
    - Installation, basic usage, advanced usage, supported functions
    - Show generated SQL for each example

14. **Update CHANGELOG.md** with actual change history

15. **Complete RBS type signatures** in `sig/active_windows.rbs`

### Phase 5 — CI & Release Readiness

16. **Expand CI matrix**
    - Test against Ruby 3.3, 3.4+
    - Optionally test against PostgreSQL (richer window function support than SQLite)

17. **Add GitHub Actions for gem publishing**

18. **Tag and release v0.2.0** after Phase 1-3 are complete
