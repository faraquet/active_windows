# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveWindows::QueryMethods do
  before do
    User.create!(name: "Alice", department: "Engineering", salary: 80_000, hire_date: Date.new(2020, 1, 1))
    User.create!(name: "Bob", department: "Engineering", salary: 90_000, hire_date: Date.new(2021, 1, 1))
    User.create!(name: "Charlie", department: "Sales", salary: 70_000, hire_date: Date.new(2020, 6, 1))
    User.create!(name: "Diana", department: "Sales", salary: 85_000, hire_date: Date.new(2019, 3, 1))
  end

  describe "class-level delegation" do
    it "delegates all window function methods" do
      ActiveWindows::QUERY_METHODS.each do |method|
        expect(User).to respond_to(method)
      end
    end
  end

  describe "#window (hash API)" do
    it "generates SQL with ROW_NUMBER window function" do
      sql = User.window(row_number: { partition: :department, order: :salary, as: :rank }).to_sql

      expect(sql).to include("ROW_NUMBER()")
      expect(sql).to include("OVER")
      expect(sql).to include('"users"."department"')
      expect(sql).to include('"users"."salary"')
      expect(sql).to include("AS rank")
    end

    it "includes all columns alongside window function" do
      sql = User.window(row_number: { order: :salary, as: :rn }).to_sql

      expect(sql).to include('"users".*')
      expect(sql).to include("ROW_NUMBER()")
    end

    it "preserves existing select when present" do
      sql = User.select(:name, :salary).window(row_number: { order: :salary, as: :rn }).to_sql

      expect(sql).to include('"users"."name"')
      expect(sql).to include('"users"."salary"')
      expect(sql).to include("ROW_NUMBER()")
      expect(sql).not_to include('"users".*')
    end

    it "works without partition (order only)" do
      sql = User.window(row_number: { order: :salary, as: :rn }).to_sql

      expect(sql).to include("ROW_NUMBER()")
      expect(sql).to include('"users"."salary"')
      expect(sql).not_to include("PARTITION BY")
    end

    it "works with multiple partition columns" do
      sql = User.window(row_number: { partition: [:department, :active], order: :salary, as: :rn }).to_sql

      expect(sql).to include('"users"."department"')
      expect(sql).to include('"users"."active"')
    end

    it "raises on unsupported options" do
      expect {
        User.window(row_number: { partition: :department, bogus: true })
      }.to raise_error(ArgumentError, /Unsupported window options.*bogus/)
    end

    it "raises with no arguments" do
      expect { User.window }.to raise_error(ArgumentError)
    end
  end

  describe "#row_number (fluent API)" do
    it "generates correct SQL via chained calls" do
      sql = User.row_number.partition_by(:department).order(:salary).as(:rank).to_sql

      expect(sql).to include("ROW_NUMBER()")
      expect(sql).to include('"users"."department"')
      expect(sql).to include('"users"."salary"')
      expect(sql).to include("AS rank")
    end

    it "works with just order" do
      sql = User.row_number.order(:salary).as(:rn).to_sql

      expect(sql).to include("ROW_NUMBER()")
      expect(sql).to include('"users"."salary"')
    end

    it "works with just as" do
      sql = User.row_number.as(:rn).to_sql

      expect(sql).to include("ROW_NUMBER()")
      expect(sql).to include("AS rn")
    end
  end

  describe "#rank" do
    it "generates RANK() SQL" do
      sql = User.rank.partition_by(:department).order(:salary).as(:salary_rank).to_sql

      expect(sql).to include("RANK()")
      expect(sql).to include("PARTITION BY")
      expect(sql).to include("AS salary_rank")
    end

    it "computes correct rank values" do
      results = User.window(rank: { partition: :department, order: :salary, as: :salary_rank })
      eng = results.select { |u| u.department == "Engineering" }.sort_by { |u| u.salary }

      expect(eng.map { |u| u.attributes["salary_rank"].to_i }).to eq([1, 2])
    end
  end

  describe "#dense_rank" do
    it "generates DENSE_RANK() SQL" do
      sql = User.dense_rank.partition_by(:department).order(:salary).as(:dr).to_sql

      expect(sql).to include("DENSE_RANK()")
      expect(sql).to include("AS dr")
    end

    it "executes and returns results" do
      results = User.dense_rank.partition_by(:department).order(:salary).as(:dr).to_a

      expect(results.length).to eq(4)
      results.each { |u| expect(u.attributes).to have_key("dr") }
    end
  end

  describe "#percent_rank" do
    it "generates PERCENT_RANK() SQL" do
      sql = User.percent_rank.order(:salary).as(:pr).to_sql

      expect(sql).to include("PERCENT_RANK()")
      expect(sql).to include("AS pr")
    end
  end

  describe "#cume_dist" do
    it "generates CUME_DIST() SQL" do
      sql = User.cume_dist.order(:salary).as(:cd).to_sql

      expect(sql).to include("CUME_DIST()")
      expect(sql).to include("AS cd")
    end
  end

  describe "#ntile" do
    it "generates NTILE(n) SQL" do
      sql = User.ntile(4).order(:salary).as(:quartile).to_sql

      expect(sql).to include("NTILE(")
      expect(sql).to include("AS quartile")
    end

    it "assigns correct bucket values" do
      results = User.ntile(2).order(:salary).as(:half).to_a

      halves = results.map { |u| u.attributes["half"].to_i }
      expect(halves).to include(1, 2)
    end
  end

  describe "#lag" do
    it "generates LAG() SQL with column and offset" do
      sql = User.lag(:salary).order(:hire_date).as(:prev_salary).to_sql

      expect(sql).to include("LAG(")
      expect(sql).to include("salary")
      expect(sql).to include("AS prev_salary")
    end

    it "accepts custom offset" do
      sql = User.lag(:salary, 2).order(:hire_date).as(:prev2).to_sql

      expect(sql).to include("LAG(")
    end

    it "accepts default value" do
      sql = User.lag(:salary, 1, 0).order(:hire_date).as(:prev_salary).to_sql

      expect(sql).to include("LAG(")
    end

    it "executes and returns results" do
      results = User.lag(:salary).order(:hire_date).as(:prev_salary).to_a

      expect(results.length).to eq(4)
      results.each { |u| expect(u.attributes).to have_key("prev_salary") }
    end
  end

  describe "#lead" do
    it "generates LEAD() SQL" do
      sql = User.lead(:salary).order(:hire_date).as(:next_salary).to_sql

      expect(sql).to include("LEAD(")
      expect(sql).to include("salary")
      expect(sql).to include("AS next_salary")
    end

    it "accepts custom offset and default" do
      sql = User.lead(:salary, 2, 0).order(:hire_date).as(:next2).to_sql

      expect(sql).to include("LEAD(")
    end

    it "executes and returns results" do
      results = User.lead(:salary).order(:hire_date).as(:next_salary).to_a

      expect(results.length).to eq(4)
    end
  end

  describe "#first_value" do
    it "generates FIRST_VALUE() SQL" do
      sql = User.first_value(:name).partition_by(:department).order(:salary).as(:lowest_paid).to_sql

      expect(sql).to include("FIRST_VALUE(")
      expect(sql).to include("name")
      expect(sql).to include("AS lowest_paid")
    end

    it "returns the first value in partition" do
      results = User.first_value(:name).partition_by(:department).order(:salary).as(:lowest_paid).to_a
      eng = results.select { |u| u.department == "Engineering" }

      eng.each { |u| expect(u.attributes["lowest_paid"]).to eq("Alice") }
    end
  end

  describe "#last_value" do
    it "generates LAST_VALUE() SQL" do
      sql = User.last_value(:name).partition_by(:department).order(:salary).as(:lv).to_sql

      expect(sql).to include("LAST_VALUE(")
      expect(sql).to include("name")
      expect(sql).to include("AS lv")
    end
  end

  describe "#nth_value" do
    it "generates NTH_VALUE() SQL" do
      sql = User.nth_value(:name, 2).partition_by(:department).order(:salary).as(:second).to_sql

      expect(sql).to include("NTH_VALUE(")
      expect(sql).to include("name")
      expect(sql).to include("AS second")
    end
  end

  describe "#window_sum" do
    it "generates SUM() OVER SQL" do
      sql = User.window_sum(:salary).partition_by(:department).as(:dept_total).to_sql

      expect(sql).to include("SUM(")
      expect(sql).to include("salary")
      expect(sql).to include("OVER")
      expect(sql).to include("AS dept_total")
    end

    it "computes correct partition sums" do
      results = User.window_sum(:salary).partition_by(:department).as(:dept_total).to_a
      eng = results.select { |u| u.department == "Engineering" }

      eng.each { |u| expect(u.attributes["dept_total"].to_i).to eq(170_000) }
    end
  end

  describe "#window_avg" do
    it "generates AVG() OVER SQL" do
      sql = User.window_avg(:salary).partition_by(:department).as(:dept_avg).to_sql

      expect(sql).to include("AVG(")
      expect(sql).to include("salary")
      expect(sql).to include("AS dept_avg")
    end

    it "computes correct partition averages" do
      results = User.window_avg(:salary).partition_by(:department).as(:dept_avg).to_a
      eng = results.select { |u| u.department == "Engineering" }

      eng.each { |u| expect(u.attributes["dept_avg"].to_f).to eq(85_000.0) }
    end
  end

  describe "#window_count" do
    it "generates COUNT() OVER SQL" do
      sql = User.window_count(:id).partition_by(:department).as(:dept_count).to_sql

      expect(sql).to include("COUNT(")
      expect(sql).to include("AS dept_count")
    end

    it "counts correctly per partition" do
      results = User.window_count(:id).partition_by(:department).as(:dept_count).to_a
      eng = results.select { |u| u.department == "Engineering" }

      eng.each { |u| expect(u.attributes["dept_count"].to_i).to eq(2) }
    end

    it "defaults to COUNT(*) when no column given" do
      sql = User.window_count.partition_by(:department).as(:cnt).to_sql

      expect(sql).to include("COUNT(")
      expect(sql).to include("*")
    end
  end

  describe "#window_min" do
    it "generates MIN() OVER SQL" do
      sql = User.window_min(:salary).partition_by(:department).as(:min_salary).to_sql

      expect(sql).to include("MIN(")
      expect(sql).to include("salary")
      expect(sql).to include("AS min_salary")
    end

    it "returns correct minimum per partition" do
      results = User.window_min(:salary).partition_by(:department).as(:min_salary).to_a
      eng = results.select { |u| u.department == "Engineering" }

      eng.each { |u| expect(u.attributes["min_salary"].to_i).to eq(80_000) }
    end
  end

  describe "#window_max" do
    it "generates MAX() OVER SQL" do
      sql = User.window_max(:salary).partition_by(:department).as(:max_salary).to_sql

      expect(sql).to include("MAX(")
      expect(sql).to include("salary")
      expect(sql).to include("AS max_salary")
    end

    it "returns correct maximum per partition" do
      results = User.window_max(:salary).partition_by(:department).as(:max_salary).to_a
      eng = results.select { |u| u.department == "Engineering" }

      eng.each { |u| expect(u.attributes["max_salary"].to_i).to eq(90_000) }
    end
  end

  describe "query execution" do
    it "returns results with window function values" do
      results = User.window(row_number: { partition: :department, order: :salary, as: :rank })

      expect(results.length).to eq(4)
      results.each do |user|
        expect(user).to respond_to(:name)
        expect(user.attributes).to have_key("rank")
      end
    end

    it "assigns correct row numbers within partitions" do
      results = User.window(row_number: { partition: :department, order: :salary, as: :rank })
      by_dept = results.group_by(&:department)

      eng = by_dept["Engineering"].sort_by { |u| u.attributes["rank"].to_i }
      expect(eng.map(&:name)).to eq(%w[Alice Bob])
      expect(eng.map { |u| u.attributes["rank"].to_i }).to eq([1, 2])

      sales = by_dept["Sales"].sort_by { |u| u.attributes["rank"].to_i }
      expect(sales.map(&:name)).to eq(%w[Charlie Diana])
      expect(sales.map { |u| u.attributes["rank"].to_i }).to eq([1, 2])
    end

    it "executes fluent chain and returns correct results" do
      results = User.row_number.partition_by(:department).order(:salary).as(:dept_rank).to_a

      expect(results.length).to eq(4)
      results.each do |user|
        expect(user.attributes).to have_key("dept_rank")
      end
    end
  end

  describe "chaining with other ActiveRecord methods" do
    it "chains with where" do
      results = User.where(department: "Engineering")
                    .window(row_number: { order: :salary, as: :rn })

      expect(results.length).to eq(2)
      expect(results.map(&:name)).to match_array(%w[Alice Bob])
    end

    it "chains with limit" do
      results = User.window(row_number: { order: :salary, as: :rn }).limit(2)

      expect(results.length).to eq(2)
    end
  end
end
