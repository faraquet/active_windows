# ActiveWindows

A Ruby DSL for SQL window functions in ActiveRecord. Write expressive window function queries using a fluent, chainable interface instead of raw SQL.

```ruby
# Fluent API
User.row_number.partition_by(:department).window_order(:salary).as(:rank)

# Hash API
User.window(row_number: { partition: :department, order: :salary, as: :rank })

# Both produce:
# SELECT "users".*, ROW_NUMBER() OVER (PARTITION BY "users"."department" ORDER BY "users"."salary") AS rank
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

Every window function method returns a chainable object with `.partition_by()`, `.window_order()`, and `.as()`:

```ruby
User.row_number.partition_by(:department).window_order(:salary).as(:rank)
```

All three chain methods are optional. The fluent API uses `.window_order()` (not `.order()`) to avoid collision with ActiveRecord's `.order()`, which controls the query-level `ORDER BY`. This lets you use both together:

```ruby
User.row_number.window_order(:salary).as(:rn).order(:name)
# Window:  OVER (ORDER BY salary)
# Query:   ORDER BY name
```

Order can be mixed freely:

```ruby
User.row_number.as(:rn).window_order(:created_at)
User.dense_rank.window_order(:score).as(:position)
```

### Hash API

Pass one or more window function definitions as a hash:

```ruby
User.window(
  row_number: { partition: :department, order: :salary, as: :rank }
)
```

The hash API uses `order:` as a key (not a method call), so there's no naming conflict with ActiveRecord's `.order()`.

Available options:

| Option | Type | Description |
|--------|------|-------------|
| `:partition` | `Symbol`, `Array` | Column(s) for `PARTITION BY` |
| `:order` | `Symbol`, `Array` | Column(s) for `ORDER BY` |
| `:as` | `Symbol` | Alias for the result column |
| `:frame` | `String` | Raw SQL frame clause (e.g. `"ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING"`) |
| `:value` | `Symbol`, `String`, `Array` | Expression(s) passed as function arguments |

### Chaining with ActiveRecord

Window functions integrate naturally with standard ActiveRecord methods:

```ruby
User.where(active: true)
    .row_number
    .partition_by(:department)
    .window_order(:salary)
    .as(:rank)

User.select(:name, :salary)
    .window(row_number: { order: :salary, as: :rn })

User.where(department: "Engineering")
    .window(rank: { order: :salary, as: :salary_rank })
    .limit(10)
```

When no `.select()` is specified, `*` is automatically included so all model columns are available alongside the window function result.

### Accessing Window Function Results

Window function values are accessible as attributes on the returned records:

```ruby
results = User.row_number.partition_by(:department).window_order(:salary).as(:rank)

results.each do |user|
  puts "#{user.name}: rank #{user.attributes['rank']}"
end
```

## Window Functions Reference

### Ranking Functions

```ruby
# ROW_NUMBER() - sequential integer within partition
User.row_number.partition_by(:department).window_order(:salary).as(:rn)

# RANK() - rank with gaps for ties
User.rank.partition_by(:department).window_order(:salary).as(:salary_rank)

# DENSE_RANK() - rank without gaps for ties
User.dense_rank.partition_by(:department).window_order(:salary).as(:dense_salary_rank)

# PERCENT_RANK() - relative rank as a fraction (0 to 1)
User.percent_rank.window_order(:salary).as(:percentile)

# CUME_DIST() - cumulative distribution (fraction of rows <= current row)
User.cume_dist.window_order(:salary).as(:cumulative)

# NTILE(n) - divide rows into n roughly equal buckets
User.ntile(4).window_order(:salary).as(:quartile)
```

### Value Functions

```ruby
# LAG(column, offset, default) - value from a preceding row
User.lag(:salary).window_order(:hire_date).as(:prev_salary)
User.lag(:salary, 2).window_order(:hire_date).as(:two_back)         # custom offset
User.lag(:salary, 1, 0).window_order(:hire_date).as(:prev_or_zero)  # with default

# LEAD(column, offset, default) - value from a following row
User.lead(:salary).window_order(:hire_date).as(:next_salary)
User.lead(:salary, 2, 0).window_order(:hire_date).as(:two_ahead)

# FIRST_VALUE(column) - first value in the window frame
User.first_value(:name).partition_by(:department).window_order(:salary).as(:lowest_paid)

# LAST_VALUE(column) - last value in the window frame
User.last_value(:name).partition_by(:department).window_order(:salary).as(:highest_paid)

# NTH_VALUE(column, n) - nth value in the window frame
User.nth_value(:name, 2).partition_by(:department).window_order(:salary).as(:second_lowest)
```

### Aggregate Window Functions

Prefixed with `window_` to avoid conflicts with ActiveRecord's built-in aggregate methods:

```ruby
# SUM(column) OVER(...)
User.window_sum(:salary).partition_by(:department).as(:dept_total)

# AVG(column) OVER(...)
User.window_avg(:salary).partition_by(:department).as(:dept_avg)

# COUNT(column) OVER(...)
User.window_count(:id).partition_by(:department).as(:dept_size)
User.window_count.partition_by(:department).as(:dept_size)  # COUNT(*)

# MIN(column) OVER(...)
User.window_min(:salary).partition_by(:department).as(:min_salary)

# MAX(column) OVER(...)
User.window_max(:salary).partition_by(:department).as(:max_salary)
```

### Window Frames

Pass a raw SQL frame clause via the hash API:

```ruby
User.window(sum: {
  value: :salary,
  partition: :department,
  order: :hire_date,
  frame: "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW",
  as: :running_total
})
```

## Examples

### Rank employees by salary within each department

```ruby
User.rank
    .partition_by(:department)
    .window_order(:salary)
    .as(:salary_rank)
```

### Running total of salaries ordered by hire date

```ruby
User.window(sum: {
  value: :salary,
  order: :hire_date,
  frame: "ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW",
  as: :running_total
})
```

### Compare each salary to the department average

```ruby
users = User.window_avg(:salary).partition_by(:department).as(:dept_avg)

users.each do |user|
  diff = user.salary - user.attributes["dept_avg"].to_f
  puts "#{user.name}: #{diff >= 0 ? '+' : ''}#{diff.round(0)} vs department average"
end
```

### Find the previous and next hire in each department

```ruby
User.lag(:name)
    .partition_by(:department)
    .window_order(:hire_date)
    .as(:previous_hire)
```

### Divide employees into salary quartiles

```ruby
User.ntile(4).window_order(:salary).as(:quartile)
```

### Rank users by total order amount (with joins)

```ruby
User.joins(:orders)
    .group(:id)
    .select("users.*, SUM(orders.amount) AS total_spent")
    .window(rank: { order: "total_spent", as: :spending_rank })
```

### Window function on joined data

```ruby
# Rank orders by amount within each user
Order.joins(:user)
     .row_number
     .partition_by("users.id")
     .window_order(amount: :desc)
     .as(:order_rank)

# Number each user's orders chronologically
Order.joins(:user)
     .select("orders.*, users.name AS user_name")
     .row_number
     .partition_by(:user_id)
     .window_order(:created_at)
     .as(:order_number)
```

### Combine window functions with scoped queries

```ruby
# Running total of order amounts per user
Order.joins(:user)
     .where(users: { department: "Engineering" })
     .window(sum: {
       value: :amount,
       partition: :user_id,
       order: :created_at,
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
