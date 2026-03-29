[![Gem Version](https://badge.fury.io/rb/active_windows.svg)](https://badge.fury.io/rb/active_windows)

# ActiveWindows

A Ruby DSL for SQL window functions in ActiveRecord. Write expressive window function queries using a fluent, chainable interface instead of raw SQL.

```ruby
# Fluent API
User.window(:row_number).partition_by(:department).order_by(:salary).as(:rank)

# Hash API
User.window(row_number: { partition_by: :department, order_by: :salary, as: :rank })

# Both produce:
# SELECT "users".*, ROW_NUMBER() OVER (PARTITION BY "users"."department" ORDER BY "users"."salary") AS "rank"
# FROM "users"
```

## Requirements

- Ruby >= 3.3
- Rails >= 8.0 (ActiveRecord >= 8.0)

## Installation

Add to your Gemfile:

```ruby
gem "active_windows"
```

Then run:

```bash
bundle install
```

ActiveWindows automatically integrates with ActiveRecord via a Rails Railtie. No additional configuration is needed.

## Usage

ActiveWindows provides two equivalent APIs: a **fluent API** with chainable methods and a **hash API** for inline definitions. Both support the same window functions and options.

### Fluent API

`window(:function_name, *args)` returns a chainable object with `.partition_by()`, `.order_by()`, and `.as()`:

```ruby
User.window(:row_number).partition_by(:department).order_by(:salary).as(:rank)

# Functions with arguments:
User.window(:lag, :salary, 1, 0).order_by(:hire_date).as(:prev_salary)
User.window(:ntile, 4).order_by(:salary).as(:quartile)
```

All three chain methods are optional. `.order_by()` sets the window's `ORDER BY`, while ActiveRecord's `.order()` controls the query-level `ORDER BY`. You can use both together:

```ruby
User.window(:row_number).order_by(:salary).as(:rn).order(:name)
# Window:  OVER (ORDER BY salary)
# Query:   ORDER BY name
```

### Hash API

Pass one or more window function definitions as a hash:

```ruby
User.window(
  row_number: { partition_by: :department, order_by: :salary, as: :rank }
)
```

Available options:

| Option | Type | Description |
|--------|------|-------------|
| `:partition_by` | `Symbol`, `Array` | Column(s) for `PARTITION BY` |
| `:order_by` | `Symbol`, `Array` | Column(s) for `ORDER BY` |
| `:as` | `Symbol` | Alias for the result column |
| `:frame` | `String` | Raw SQL frame clause (e.g. `"ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING"`) |
| `:value` | `Symbol`, `String`, `Array` | Expression(s) passed as function arguments |
| `:over` | `Symbol` | Reference to a named window defined via `define:` |

### Association Names

You can use `belongs_to` association names instead of foreign key columns. ActiveWindows automatically resolves them:

```ruby
# These are equivalent:
Order.window(:row_number).partition_by(:user).order_by(:amount).as(:rn)
Order.window(:row_number).partition_by(:user_id).order_by(:amount).as(:rn)

# Works in the hash API too:
Order.window(row_number: { partition_by: :user, order_by: :amount, as: :rn })
```

### Chaining with ActiveRecord

Window functions integrate naturally with standard ActiveRecord methods:

```ruby
User.where(active: true)
    .window(:row_number)
    .partition_by(:department)
    .order_by(:salary)
    .as(:rank)

User.select(:name, :salary)
    .window(row_number: { order_by: :salary, as: :rn })

User.where(department: "Engineering")
    .window(rank: { order_by: :salary, as: :salary_rank })
    .limit(10)
```

When no `.select()` is specified, `*` is automatically included so all model columns are available alongside the window function result.

### Accessing Window Function Results

Window function values are accessible as attributes on the returned records:

```ruby
results = User.window(:row_number).partition_by(:department).order_by(:salary).as(:rank)

results.each do |user|
  puts "#{user.name}: rank #{user.attributes['rank']}"
end
```

## Window Functions Reference

### Ranking Functions

```ruby
# ROW_NUMBER() - sequential integer within partition
User.window(:row_number).partition_by(:department).order_by(:salary).as(:rn)

# RANK() - rank with gaps for ties
User.window(:rank).partition_by(:department).order_by(:salary).as(:salary_rank)

# DENSE_RANK() - rank without gaps for ties
User.window(:dense_rank).partition_by(:department).order_by(:salary).as(:dense_salary_rank)

# PERCENT_RANK() - relative rank as a fraction (0 to 1)
User.window(:percent_rank).order_by(:salary).as(:percentile)

# CUME_DIST() - cumulative distribution (fraction of rows <= current row)
User.window(:cume_dist).order_by(:salary).as(:cumulative)

# NTILE(n) - divide rows into n roughly equal buckets
User.window(:ntile, 4).order_by(:salary).as(:quartile)
```

### Value Functions

```ruby
# LAG(column, offset, default) - value from a preceding row
User.window(:lag, :salary).order_by(:hire_date).as(:prev_salary)
User.window(:lag, :salary, 2).order_by(:hire_date).as(:two_back)         # custom offset
User.window(:lag, :salary, 1, 0).order_by(:hire_date).as(:prev_or_zero)  # with default

# LEAD(column, offset, default) - value from a following row
User.window(:lead, :salary).order_by(:hire_date).as(:next_salary)
User.window(:lead, :salary, 2, 0).order_by(:hire_date).as(:two_ahead)

# FIRST_VALUE(column) - first value in the window frame
User.window(:first_value, :name).partition_by(:department).order_by(:salary).as(:lowest_paid)

# LAST_VALUE(column) - last value in the window frame
User.window(:last_value, :name).partition_by(:department).order_by(:salary).as(:highest_paid)

# NTH_VALUE(column, n) - nth value in the window frame
User.window(:nth_value, :name, 2).partition_by(:department).order_by(:salary).as(:second_lowest)
```

### Aggregate Window Functions

```ruby
# SUM(column) OVER(...)
User.window(:sum, :salary).partition_by(:department).as(:dept_total)

# AVG(column) OVER(...)
User.window(:avg, :salary).partition_by(:department).as(:dept_avg)

# COUNT(column) OVER(...)
User.window(:count, :id).partition_by(:department).as(:dept_size)
User.window(:count, "*").partition_by(:department).as(:dept_size)  # COUNT(*)

# MIN(column) OVER(...)
User.window(:min, :salary).partition_by(:department).as(:min_salary)

# MAX(column) OVER(...)
User.window(:max, :salary).partition_by(:department).as(:max_salary)
```

### Named Windows

Define a window once and reuse it across multiple functions with `define:` and `over:`:

```ruby
User.window(
  define: { w: { partition_by: :department, order_by: :salary } },
  row_number: { over: :w, as: :rn },
  rank:       { over: :w, as: :salary_rank },
  sum:        { value: :salary, over: :w, as: :running_total }
)
```

You can define multiple windows and extend them per-function:

```ruby
User.window(
  define: {
    by_dept:  { partition_by: :department },
    globally: { order_by: :salary }
  },
  row_number: { over: :by_dept, order_by: :salary, as: :dept_rn },
  rank:       { over: :globally, as: :global_rank }
)
```

Options on the function (like `order_by:`) are merged with the named definition, so you can share the common parts and specialize per-function.

### Window Frames

Use a hash DSL to define frame clauses:

```ruby
# ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
User.window(sum: {
  value: :salary,
  partition_by: :department,
  order_by: :hire_date,
  frame: { rows: [:unbounded_preceding, :current_row] },
  as: :running_total
})

# ROWS BETWEEN 3 PRECEDING AND 1 FOLLOWING
frame: { rows: [3, -1] }

# RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
frame: { range: [:unbounded_preceding, :unbounded_following] }

# Single bound: ROWS UNBOUNDED PRECEDING
frame: { rows: :unbounded_preceding }
```

Available bounds: `:unbounded_preceding`, `:unbounded_following`, `:current_row`, or an integer (positive = PRECEDING, negative = FOLLOWING).

Fluent API:

```ruby
User.window(:sum, :salary)
    .partition_by(:department)
    .order_by(:hire_date)
    .frame(rows: [:unbounded_preceding, :current_row])
    .as(:running_total)
```

Raw SQL strings are also accepted:

```ruby
frame: "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"
```

## Examples

### Rank employees by salary within each department

```ruby
User.window(:rank)
    .partition_by(:department)
    .order_by(:salary)
    .as(:salary_rank)
```

### Running total of salaries ordered by hire date

```ruby
User.window(sum: {
  value: :salary,
  order_by: :hire_date,
  frame: "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW",
  as: :running_total
})
```

### Compare each salary to the department average

```ruby
users = User.window(:avg, :salary).partition_by(:department).as(:dept_avg)

users.each do |user|
  diff = user.salary - user.attributes["dept_avg"].to_f
  puts "#{user.name}: #{diff >= 0 ? '+' : ''}#{diff.round(0)} vs department average"
end
```

### Find the previous and next hire in each department

```ruby
User.window(:lag, :name)
    .partition_by(:department)
    .order_by(:hire_date)
    .as(:previous_hire)
```

### Divide employees into salary quartiles

```ruby
User.window(:ntile, 4).order_by(:salary).as(:quartile)
```

### Rank users by total order amount (with joins)

```ruby
User.joins(:orders)
    .group(:id)
    .select("users.*, SUM(orders.amount) AS total_spent")
    .window(rank: { order_by: "total_spent", as: :spending_rank })
```

### Window function on joined data

```ruby
# Rank orders by amount within each user
Order.joins(:user)
     .window(:row_number)
     .partition_by("users.id")
     .order_by(amount: :desc)
     .as(:order_rank)

# Number each user's orders chronologically
Order.joins(:user)
     .select("orders.*, users.name AS user_name")
     .window(:row_number)
     .partition_by(:user_id)
     .order_by(:created_at)
     .as(:order_number)
```

### Combine window functions with scoped queries

```ruby
# Running total of order amounts per user
Order.joins(:user)
     .where(users: { department: "Engineering" })
     .window(sum: {
       value: :amount,
       partition_by: :user_id,
       order_by: :created_at,
       frame: "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW",
       as: :running_total
     })
```

## Development

```bash
bundle install
bundle exec rake test
```

Run tests against a specific database:

```bash
# SQLite (default)
bundle exec rake test

# PostgreSQL
DB_ADAPTER=postgresql POSTGRES_DB=active_windows_test bundle exec rake test

# MySQL
DB_ADAPTER=mysql2 MYSQL_DB=active_windows_test bundle exec rake test
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/faraquet/active_windows.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
