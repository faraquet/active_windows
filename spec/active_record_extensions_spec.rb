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
    it "delegates window and row_number to all" do
      expect(User).to respond_to(:window)
      expect(User).to respond_to(:row_number)
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

  describe "query execution" do
    it "returns results with window function values" do
      results = User.window(row_number: { partition: :department, order: :salary, as: :rank })

      expect(results.length).to eq(4)
      results.each do |user|
        expect(user).to respond_to(:name)
        # Window function alias is accessible as an attribute
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
