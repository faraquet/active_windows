# frozen_string_literal: true

require "test_helper"

class QueryMethodsTest < Minitest::Test
  def setup
    Order.delete_all
    User.delete_all
    User.create!(name: "Alice", department: "Engineering", salary: 80_000, hire_date: Date.new(2020, 1, 1))
    User.create!(name: "Bob", department: "Engineering", salary: 90_000, hire_date: Date.new(2021, 1, 1))
    User.create!(name: "Charlie", department: "Sales", salary: 70_000, hire_date: Date.new(2020, 6, 1))
    User.create!(name: "Diana", department: "Sales", salary: 85_000, hire_date: Date.new(2019, 3, 1))
  end

  private

  # Adapter-agnostic quoting helpers
  def q(name)
    User.connection.quote_column_name(name)
  end

  def quoted_table(table, column)
    "#{q(table)}.#{q(column)}"
  end

  def col(column)
    quoted_table("users", column)
  end

  public

  # Class-level delegation

  def test_delegates_window_method
    assert_respond_to User, :window
  end

  # Hash API

  def test_window_generates_row_number_sql
    sql = User.window(row_number: { partition_by: :department, order_by: :salary, as: :rank }).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, "OVER"
    assert_includes sql, col("department")
    assert_includes sql, col("salary")
    assert_includes sql, "AS #{q('rank')}"
  end

  def test_window_includes_all_columns
    sql = User.window(row_number: { order_by: :salary, as: :rn }).to_sql

    assert_includes sql, "#{q('users')}.*"
    assert_includes sql, "ROW_NUMBER()"
  end

  def test_window_preserves_existing_select
    sql = User.select(:name, :salary).window(row_number: { order_by: :salary, as: :rn }).to_sql

    assert_includes sql, col("name")
    assert_includes sql, col("salary")
    assert_includes sql, "ROW_NUMBER()"
    refute_includes sql, "#{q('users')}.*"
  end

  def test_window_without_partition
    sql = User.window(row_number: { order_by: :salary, as: :rn }).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, col("salary")
    refute_includes sql, "PARTITION BY"
  end

  def test_window_with_multiple_partition_columns
    sql = User.window(row_number: { partition_by: [:department, :active], order_by: :salary, as: :rn }).to_sql

    assert_includes sql, col("department")
    assert_includes sql, col("active")
  end

  def test_window_raises_on_unsupported_options
    error = assert_raises(ArgumentError) do
      User.window(row_number: { partition_by: :department, bogus: true })
    end
    assert_match(/Unsupported window options.*bogus/, error.message)
  end

  def test_window_raises_with_no_arguments
    assert_raises(ArgumentError) { User.window }
  end

  # Fluent API via window(:symbol)

  def test_window_symbol_returns_chain
    sql = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rank).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, col("department")
    assert_includes sql, col("salary")
    assert_includes sql, "AS #{q('rank')}"
  end

  def test_window_symbol_with_function_args
    sql = User.window(:lag, :salary, 1, 0).order_by(:hire_date).as(:prev_salary).to_sql

    assert_includes sql, "LAG("
    assert_includes sql, "AS #{q('prev_salary')}"
  end

  def test_window_symbol_ntile
    results = User.window(:ntile, 2).order_by(:salary).as(:half).to_a
    halves = results.map { |u| u.attributes["half"].to_i }

    assert_includes halves, 1
    assert_includes halves, 2
  end

  def test_window_symbol_executes_correctly
    results = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rn).to_a

    assert_equal 4, results.length
    results.each { |u| assert_includes u.attributes.keys, "rn" }
  end

  def test_window_row_number_with_just_order
    sql = User.window(:row_number).order_by(:salary).as(:rn).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, col("salary")
  end

  def test_window_row_number_with_just_as
    sql = User.window(:row_number).as(:rn).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, "AS #{q('rn')}"
  end

  # Rank

  def test_rank_generates_sql
    sql = User.window(:rank).partition_by(:department).order_by(:salary).as(:salary_rank).to_sql

    assert_includes sql, "RANK()"
    assert_includes sql, "PARTITION BY"
    assert_includes sql, "AS #{q('salary_rank')}"
  end

  def test_rank_computes_correct_values
    results = User.window(rank: { partition_by: :department, order_by: :salary, as: :salary_rank })
    eng = results.select { |u| u.department == "Engineering" }.sort_by(&:salary)

    assert_equal [1, 2], eng.map { |u| u.attributes["salary_rank"].to_i }
  end

  # Dense rank

  def test_dense_rank_generates_sql
    sql = User.window(:dense_rank).partition_by(:department).order_by(:salary).as(:dr).to_sql

    assert_includes sql, "DENSE_RANK()"
    assert_includes sql, "AS #{q('dr')}"
  end

  def test_dense_rank_executes_and_returns_results
    results = User.window(:dense_rank).partition_by(:department).order_by(:salary).as(:dr).to_a

    assert_equal 4, results.length
    results.each { |u| assert_includes u.attributes.keys, "dr" }
  end

  # Percent rank

  def test_percent_rank_generates_sql
    sql = User.window(:percent_rank).order_by(:salary).as(:pr).to_sql

    assert_includes sql, "PERCENT_RANK()"
    assert_includes sql, "AS #{q('pr')}"
  end

  # Cume dist

  def test_cume_dist_generates_sql
    sql = User.window(:cume_dist).order_by(:salary).as(:cd).to_sql

    assert_includes sql, "CUME_DIST()"
    assert_includes sql, "AS #{q('cd')}"
  end

  # Ntile

  def test_ntile_generates_sql
    sql = User.window(:ntile, 4).order_by(:salary).as(:quartile).to_sql

    assert_includes sql, "NTILE("
    assert_includes sql, "AS #{q('quartile')}"
  end

  def test_ntile_assigns_correct_bucket_values
    results = User.window(:ntile, 2).order_by(:salary).as(:half).to_a
    halves = results.map { |u| u.attributes["half"].to_i }

    assert_includes halves, 1
    assert_includes halves, 2
  end

  # Lag

  def test_lag_generates_sql
    sql = User.window(:lag, :salary).order_by(:hire_date).as(:prev_salary).to_sql

    assert_includes sql, "LAG("
    assert_includes sql, "salary"
    assert_includes sql, "AS #{q('prev_salary')}"
  end

  def test_lag_accepts_custom_offset
    sql = User.window(:lag, :salary, 2).order_by(:hire_date).as(:prev2).to_sql

    assert_includes sql, "LAG("
  end

  def test_lag_accepts_default_value
    sql = User.window(:lag, :salary, 1, 0).order_by(:hire_date).as(:prev_salary).to_sql

    assert_includes sql, "LAG("
  end

  def test_lag_executes_and_returns_results
    results = User.window(:lag, :salary).order_by(:hire_date).as(:prev_salary).to_a

    assert_equal 4, results.length
    results.each { |u| assert_includes u.attributes.keys, "prev_salary" }
  end

  # Lead

  def test_lead_generates_sql
    sql = User.window(:lead, :salary).order_by(:hire_date).as(:next_salary).to_sql

    assert_includes sql, "LEAD("
    assert_includes sql, "salary"
    assert_includes sql, "AS #{q('next_salary')}"
  end

  def test_lead_accepts_custom_offset_and_default
    sql = User.window(:lead, :salary, 2, 0).order_by(:hire_date).as(:next2).to_sql

    assert_includes sql, "LEAD("
  end

  def test_lead_executes_and_returns_results
    results = User.window(:lead, :salary).order_by(:hire_date).as(:next_salary).to_a

    assert_equal 4, results.length
  end

  # First value

  def test_first_value_generates_sql
    sql = User.window(:first_value, :name).partition_by(:department).order_by(:salary).as(:lowest_paid).to_sql

    assert_includes sql, "FIRST_VALUE("
    assert_includes sql, "name"
    assert_includes sql, "AS #{q('lowest_paid')}"
  end

  def test_first_value_returns_correct_value
    results = User.window(:first_value, :name).partition_by(:department).order_by(:salary).as(:lowest_paid).to_a
    eng = results.select { |u| u.department == "Engineering" }

    eng.each { |u| assert_equal "Alice", u.attributes["lowest_paid"] }
  end

  # Last value

  def test_last_value_generates_sql
    sql = User.window(:last_value, :name).partition_by(:department).order_by(:salary).as(:lv).to_sql

    assert_includes sql, "LAST_VALUE("
    assert_includes sql, "name"
    assert_includes sql, "AS #{q('lv')}"
  end

  # Nth value

  def test_nth_value_generates_sql
    sql = User.window(:nth_value, :name, 2).partition_by(:department).order_by(:salary).as(:second).to_sql

    assert_includes sql, "NTH_VALUE("
    assert_includes sql, "name"
    assert_includes sql, "AS #{q('second')}"
  end

  # Window sum

  def test_window_sum_generates_sql
    sql = User.window(:sum, :salary).partition_by(:department).as(:dept_total).to_sql

    assert_includes sql, "SUM("
    assert_includes sql, "salary"
    assert_includes sql, "OVER"
    assert_includes sql, "AS #{q('dept_total')}"
  end

  def test_window_sum_computes_correct_partition_sums
    results = User.window(:sum, :salary).partition_by(:department).as(:dept_total).to_a
    eng = results.select { |u| u.department == "Engineering" }

    eng.each { |u| assert_equal 170_000, u.attributes["dept_total"].to_i }
  end

  # Window avg

  def test_window_avg_generates_sql
    sql = User.window(:avg, :salary).partition_by(:department).as(:dept_avg).to_sql

    assert_includes sql, "AVG("
    assert_includes sql, "salary"
    assert_includes sql, "AS #{q('dept_avg')}"
  end

  def test_window_avg_computes_correct_partition_averages
    results = User.window(:avg, :salary).partition_by(:department).as(:dept_avg).to_a
    eng = results.select { |u| u.department == "Engineering" }

    eng.each { |u| assert_equal 85_000.0, u.attributes["dept_avg"].to_f }
  end

  # Window count

  def test_window_count_generates_sql
    sql = User.window(:count, :id).partition_by(:department).as(:dept_count).to_sql

    assert_includes sql, "COUNT("
    assert_includes sql, "AS #{q('dept_count')}"
  end

  def test_window_count_counts_correctly_per_partition
    results = User.window(:count, :id).partition_by(:department).as(:dept_count).to_a
    eng = results.select { |u| u.department == "Engineering" }

    eng.each { |u| assert_equal 2, u.attributes["dept_count"].to_i }
  end

  def test_window_count_defaults_to_star
    sql = User.window(:count, "*").partition_by(:department).as(:cnt).to_sql

    assert_includes sql, "COUNT("
    assert_includes sql, "*"
  end

  # Window min

  def test_window_min_generates_sql
    sql = User.window(:min, :salary).partition_by(:department).as(:min_salary).to_sql

    assert_includes sql, "MIN("
    assert_includes sql, "salary"
    assert_includes sql, "AS #{q('min_salary')}"
  end

  def test_window_min_returns_correct_minimum
    results = User.window(:min, :salary).partition_by(:department).as(:min_salary).to_a
    eng = results.select { |u| u.department == "Engineering" }

    eng.each { |u| assert_equal 80_000, u.attributes["min_salary"].to_i }
  end

  # Window max

  def test_window_max_generates_sql
    sql = User.window(:max, :salary).partition_by(:department).as(:max_salary).to_sql

    assert_includes sql, "MAX("
    assert_includes sql, "salary"
    assert_includes sql, "AS #{q('max_salary')}"
  end

  def test_window_max_returns_correct_maximum
    results = User.window(:max, :salary).partition_by(:department).as(:max_salary).to_a
    eng = results.select { |u| u.department == "Engineering" }

    eng.each { |u| assert_equal 90_000, u.attributes["max_salary"].to_i }
  end

  # Query execution

  def test_returns_results_with_window_function_values
    results = User.window(row_number: { partition_by: :department, order_by: :salary, as: :rank })

    assert_equal 4, results.length
    results.each do |user|
      assert_respond_to user, :name
      assert_includes user.attributes.keys, "rank"
    end
  end

  def test_assigns_correct_row_numbers_within_partitions
    results = User.window(row_number: { partition_by: :department, order_by: :salary, as: :rank })
    by_dept = results.group_by(&:department)

    eng = by_dept["Engineering"].sort_by { |u| u.attributes["rank"].to_i }
    assert_equal %w[Alice Bob], eng.map(&:name)
    assert_equal [1, 2], eng.map { |u| u.attributes["rank"].to_i }

    sales = by_dept["Sales"].sort_by { |u| u.attributes["rank"].to_i }
    assert_equal %w[Charlie Diana], sales.map(&:name)
    assert_equal [1, 2], sales.map { |u| u.attributes["rank"].to_i }
  end

  def test_fluent_chain_executes_and_returns_correct_results
    results = User.window(:row_number).partition_by(:department).order_by(:salary).as(:dept_rank).to_a

    assert_equal 4, results.length
    results.each { |u| assert_includes u.attributes.keys, "dept_rank" }
  end

  # Ordering direction

  def test_order_desc_with_hash_in_fluent_api
    sql = User.window(:row_number).partition_by(:department).order_by(salary: :desc).as(:rn).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, "#{col('salary')} DESC"
  end

  def test_order_asc_with_hash_in_fluent_api
    sql = User.window(:row_number).order_by(salary: :asc).as(:rn).to_sql

    assert_includes sql, "#{col('salary')} ASC"
  end

  def test_order_desc_with_hash_api
    sql = User.window(row_number: { order_by: { salary: :desc }, as: :rn }).to_sql

    assert_includes sql, "#{col('salary')} DESC"
  end

  def test_order_mixed_directions
    sql = User.window(:row_number).order_by({ department: :asc }, { salary: :desc }).as(:rn).to_sql

    assert_includes sql, "#{col('department')} ASC"
    assert_includes sql, "#{col('salary')} DESC"
  end

  def test_order_desc_produces_correct_results
    results = User.window(:row_number).partition_by(:department).order_by(salary: :desc).as(:rn).to_a
    eng = results.select { |u| u.department == "Engineering" }.sort_by { |u| u.attributes["rn"].to_i }

    assert_equal %w[Bob Alice], eng.map(&:name)
    assert_equal [1, 2], eng.map { |u| u.attributes["rn"].to_i }
  end

  def test_order_symbol_still_defaults_to_asc
    results = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rn).to_a
    eng = results.select { |u| u.department == "Engineering" }.sort_by { |u| u.attributes["rn"].to_i }

    assert_equal %w[Alice Bob], eng.map(&:name)
  end

  # Chaining with ActiveRecord

  def test_chains_with_where
    results = User.where(department: "Engineering")
                  .window(row_number: { order_by: :salary, as: :rn })

    assert_equal 2, results.length
    assert_equal %w[Alice Bob], results.map(&:name).sort
  end

  def test_chains_with_limit
    results = User.window(row_number: { order_by: :salary, as: :rn }).limit(2)

    assert_equal 2, results.length
  end

  # Multiple window functions in one call

  def test_multiple_window_functions_in_hash_api
    sql = User.window(
      row_number: { partition_by: :department, order_by: :salary, as: :rn },
      rank: { partition_by: :department, order_by: :salary, as: :salary_rank }
    ).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, "AS #{q('rn')}"
    assert_includes sql, "RANK()"
    assert_includes sql, "AS #{q('salary_rank')}"
  end

  def test_multiple_window_functions_return_correct_results
    results = User.window(
      row_number: { partition_by: :department, order_by: :salary, as: :rn },
      rank: { partition_by: :department, order_by: :salary, as: :salary_rank }
    )

    assert_equal 4, results.length
    results.each do |user|
      assert_includes user.attributes.keys, "rn"
      assert_includes user.attributes.keys, "salary_rank"
    end
  end

  def test_multiple_window_functions_values_are_correct
    results = User.window(
      row_number: { partition_by: :department, order_by: :salary, as: :rn },
      sum: { value: :salary, partition_by: :department, as: :dept_total }
    )
    eng = results.select { |u| u.department == "Engineering" }.sort_by { |u| u.attributes["rn"].to_i }

    assert_equal [1, 2], eng.map { |u| u.attributes["rn"].to_i }
    eng.each { |u| assert_equal 170_000, u.attributes["dept_total"].to_i }
  end

  def test_chaining_multiple_window_calls
    results = User.window(row_number: { order_by: :salary, as: :rn })
                  .window(rank: { order_by: :salary, as: :salary_rank })

    assert_equal 4, results.length
    results.each do |user|
      assert_includes user.attributes.keys, "rn"
      assert_includes user.attributes.keys, "salary_rank"
    end
  end

  # Frame DSL

  def test_frame_hash_rows_between
    sql = User.window(sum: {
      value: :salary,
      partition_by: :department,
      order_by: :hire_date,
      frame: { rows: [:unbounded_preceding, :current_row] },
      as: :running_total
    }).to_sql

    assert_includes sql, "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"
  end

  def test_frame_hash_rows_between_with_offsets
    sql = User.window(sum: {
      value: :salary,
      order_by: :hire_date,
      frame: { rows: [3, -1] },
      as: :running_total
    }).to_sql

    assert_includes sql, "ROWS BETWEEN 3 PRECEDING AND 1 FOLLOWING"
  end

  def test_frame_hash_range_unbounded
    sql = User.window(sum: {
      value: :salary,
      partition_by: :department,
      frame: { range: [:unbounded_preceding, :unbounded_following] },
      as: :dept_total
    }).to_sql

    assert_includes sql, "RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING"
  end

  def test_frame_hash_single_bound
    sql = User.window(sum: {
      value: :salary,
      order_by: :salary,
      frame: { rows: :current_row },
      as: :just_me
    }).to_sql

    assert_includes sql, "ROWS CURRENT ROW"
  end

  def test_frame_hash_single_bound_preceding
    sql = User.window(sum: {
      value: :salary,
      order_by: :salary,
      frame: { rows: :unbounded_preceding },
      as: :running
    }).to_sql

    assert_includes sql, "ROWS UNBOUNDED PRECEDING"
  end

  def test_frame_raw_string_still_works
    sql = User.window(sum: {
      value: :salary,
      order_by: :hire_date,
      frame: "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW",
      as: :running_total
    }).to_sql

    assert_includes sql, "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"
  end

  def test_frame_in_fluent_api
    sql = User.window(:sum, :salary)
              .partition_by(:department)
              .order_by(:hire_date)
              .frame(rows: [:unbounded_preceding, :current_row])
              .as(:running_total)
              .to_sql

    assert_includes sql, "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"
  end

  def test_frame_produces_correct_running_total
    results = User.window(sum: {
      value: :salary,
      partition_by: :department,
      order_by: :salary,
      frame: { rows: [:unbounded_preceding, :current_row] },
      as: :running_total
    }).to_a
    eng = results.select { |u| u.department == "Engineering" }.sort_by(&:salary)

    assert_equal 80_000, eng[0].attributes["running_total"].to_i
    assert_equal 170_000, eng[1].attributes["running_total"].to_i
  end

  def test_frame_raises_on_invalid_type
    error = assert_raises(ArgumentError) do
      User.window(sum: { value: :salary, frame: { groups: [:current_row] }, as: :x })
    end
    assert_match(/Invalid frame type/, error.message)
  end

  def test_frame_raises_on_invalid_bound
    error = assert_raises(ArgumentError) do
      User.window(sum: { value: :salary, frame: { rows: [:bogus] }, as: :x })
    end
    assert_match(/Invalid frame bound/, error.message)
  end

  # Named windows (define/over)

  def test_named_window_generates_correct_sql
    sql = User.window(
      define: { w: { partition_by: :department, order_by: :salary } },
      row_number: { over: :w, as: :rn },
      rank: { over: :w, as: :salary_rank }
    ).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, "RANK()"
    assert_includes sql, col("department")
    assert_includes sql, col("salary")
    assert_includes sql, "AS #{q('rn')}"
    assert_includes sql, "AS #{q('salary_rank')}"
  end

  def test_named_window_produces_correct_results
    results = User.window(
      define: { w: { partition_by: :department, order_by: :salary } },
      row_number: { over: :w, as: :rn },
      rank: { over: :w, as: :salary_rank }
    )

    assert_equal 4, results.length
    results.each do |user|
      assert_includes user.attributes.keys, "rn"
      assert_includes user.attributes.keys, "salary_rank"
    end
  end

  def test_named_window_with_value_function
    results = User.window(
      define: { w: { partition_by: :department } },
      row_number: { over: :w, order_by: :salary, as: :rn },
      sum: { value: :salary, over: :w, as: :dept_total }
    )
    eng = results.select { |u| u.department == "Engineering" }.sort_by { |u| u.attributes["rn"].to_i }

    assert_equal [1, 2], eng.map { |u| u.attributes["rn"].to_i }
    eng.each { |u| assert_equal 170_000, u.attributes["dept_total"].to_i }
  end

  def test_named_window_with_multiple_definitions
    sql = User.window(
      define: {
        by_dept: { partition_by: :department, order_by: :salary },
        global: { order_by: :salary }
      },
      row_number: { over: :by_dept, as: :dept_rn },
      rank: { over: :global, as: :global_rank }
    ).to_sql

    assert_includes sql, "ROW_NUMBER()"
    assert_includes sql, "RANK()"
    assert_includes sql, "PARTITION BY"
    assert_includes sql, "AS #{q('dept_rn')}"
    assert_includes sql, "AS #{q('global_rank')}"
  end

  def test_named_window_over_can_be_extended
    sql = User.window(
      define: { w: { partition_by: :department } },
      row_number: { over: :w, order_by: :salary, as: :rn }
    ).to_sql

    assert_includes sql, "PARTITION BY"
    assert_includes sql, col("salary")
    assert_includes sql, "AS #{q('rn')}"
  end

  def test_named_window_raises_on_unknown_reference
    error = assert_raises(ArgumentError) do
      User.window(
        row_number: { over: :nonexistent, as: :rn }
      )
    end
    assert_match(/Unknown window definition: nonexistent/, error.message)
  end

  # Window order_by vs ActiveRecord order

  def test_order_by_sets_window_order_and_ar_order_sets_query_order
    sql = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rn)
              .order(:name).to_sql

    # Window ORDER BY
    assert_includes sql, "OVER (PARTITION BY"
    assert_includes sql, col("salary")
    # Query ORDER BY
    assert_match(/ORDER BY #{Regexp.escape(col('name'))}/i, sql)
  end

  def test_order_by_and_ar_order_produce_correct_results
    results = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rn)
                  .order(name: :asc).to_a

    # Query-level order: alphabetical by name
    assert_equal %w[Alice Bob Charlie Diana], results.map(&:name)
    # Window-level order: row numbers based on salary within department
    results.each { |u| assert_includes u.attributes.keys, "rn" }
  end

  # Edge cases — empty result sets

  def test_window_on_empty_result_set
    User.delete_all
    results = User.window(row_number: { order_by: :salary, as: :rn }).to_a

    assert_empty results
  end

  def test_window_on_empty_filtered_result
    results = User.where(department: "Nonexistent")
                  .window(row_number: { order_by: :salary, as: :rn }).to_a

    assert_empty results
  end

  # Edge cases — single-row partitions

  def test_window_with_single_row_partition
    User.delete_all
    User.create!(name: "Solo", department: "Legal", salary: 75_000, hire_date: Date.new(2022, 1, 1))

    results = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rn).to_a

    assert_equal 1, results.length
    assert_equal 1, results.first.attributes["rn"].to_i
  end

  def test_aggregate_window_on_single_row_partition
    User.delete_all
    User.create!(name: "Solo", department: "Legal", salary: 75_000, hire_date: Date.new(2022, 1, 1))

    results = User.window(:sum, :salary).partition_by(:department).as(:dept_total).to_a

    assert_equal 1, results.length
    assert_equal 75_000, results.first.attributes["dept_total"].to_i
  end

  # Edge cases — NULL values

  def test_window_with_null_partition_column
    User.create!(name: "Eve", department: nil, salary: 60_000, hire_date: Date.new(2023, 1, 1))

    results = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rn).to_a
    null_dept = results.select { |u| u.department.nil? }

    assert_equal 1, null_dept.length
    assert_equal 1, null_dept.first.attributes["rn"].to_i
  end

  def test_window_with_null_order_column
    User.create!(name: "Eve", department: "Engineering", salary: nil, hire_date: Date.new(2023, 1, 1))

    results = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rn).to_a

    assert_equal 5, results.length
    results.each { |u| assert_includes u.attributes.keys, "rn" }
  end

  def test_window_with_null_value_column
    User.create!(name: "Eve", department: "Engineering", salary: nil, hire_date: Date.new(2023, 1, 1))

    results = User.window(:sum, :salary).partition_by(:department).as(:dept_total).to_a
    eng = results.select { |u| u.department == "Engineering" }

    assert_equal 3, eng.length
    # SUM ignores NULLs
    eng.each { |u| assert_equal 170_000, u.attributes["dept_total"].to_i }
  end

  # Edge cases — chaining with joins, group, includes

  def test_chains_with_joins
    alice = User.find_by(name: "Alice")
    Order.create!(user: alice, amount: 100)
    Order.create!(user: alice, amount: 200)

    results = User.joins(:orders)
                  .window(row_number: { order_by: :salary, as: :rn })

    assert_equal 2, results.length
    results.each { |u| assert_includes u.attributes.keys, "rn" }
  end

  def test_chains_with_includes
    results = User.includes(:orders)
                  .window(row_number: { order_by: :salary, as: :rn })

    assert_equal 4, results.length
    results.each { |u| assert_includes u.attributes.keys, "rn" }
  end

  def test_chains_with_where_and_joins
    alice = User.find_by(name: "Alice")
    bob = User.find_by(name: "Bob")
    Order.create!(user: alice, amount: 100)
    Order.create!(user: bob, amount: 300)

    results = User.joins(:orders)
                  .where(department: "Engineering")
                  .window(row_number: { order_by: :salary, as: :rn })

    assert_equal 2, results.length
    assert_equal %w[Alice Bob], results.map(&:name).sort
  end

  # Association name resolution

  def test_partition_by_association_name_resolves_to_foreign_key
    alice = User.find_by(name: "Alice")
    bob = User.find_by(name: "Bob")
    Order.create!(user: alice, amount: 100)
    Order.create!(user: alice, amount: 200)
    Order.create!(user: bob, amount: 300)

    sql = Order.window(:row_number).partition_by(:user).order_by(:amount).as(:rn).to_sql

    assert_includes sql, Order.connection.quote_column_name("user_id")
    refute_includes sql, "\"user\""
  end

  def test_partition_by_association_name_produces_correct_results
    alice = User.find_by(name: "Alice")
    bob = User.find_by(name: "Bob")
    Order.create!(user: alice, amount: 100)
    Order.create!(user: alice, amount: 200)
    Order.create!(user: bob, amount: 300)

    results = Order.window(:row_number).partition_by(:user).order_by(:amount).as(:rn).to_a

    alice_orders = results.select { |o| o.user_id == alice.id }.sort_by { |o| o.attributes["rn"].to_i }
    assert_equal [1, 2], alice_orders.map { |o| o.attributes["rn"].to_i }

    bob_orders = results.select { |o| o.user_id == bob.id }
    assert_equal [1], bob_orders.map { |o| o.attributes["rn"].to_i }
  end

  def test_order_by_association_name_resolves_to_foreign_key
    alice = User.find_by(name: "Alice")
    Order.create!(user: alice, amount: 100)

    sql = Order.window(:row_number).order_by(:user).as(:rn).to_sql

    assert_includes sql, Order.connection.quote_column_name("user_id")
  end

  def test_hash_api_with_association_name
    alice = User.find_by(name: "Alice")
    Order.create!(user: alice, amount: 100)
    Order.create!(user: alice, amount: 200)

    sql = Order.window(row_number: { partition_by: :user, order_by: :amount, as: :rn }).to_sql

    assert_includes sql, Order.connection.quote_column_name("user_id")
  end

  def test_actual_column_name_still_works
    sql = Order.window(:row_number).partition_by(:user_id).order_by(:amount).as(:rn).to_sql

    assert_includes sql, Order.connection.quote_column_name("user_id")
  end
end
