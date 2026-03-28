# frozen_string_literal: true

require "active_record"

module ActiveWindows
  class WindowChain
    attr_reader :function, :alias_name, :partition_columns, :order_columns, :function_args

    def initialize(function, relation, function_args: [])
      @function = function
      @relation = relation
      @function_args = function_args
      @alias_name = nil
      @partition_columns = []
      @order_columns = []
    end

    def as(name)
      @alias_name = name
      self
    end

    def partition_by(*columns)
      @partition_columns = columns.flatten
      self
    end

    def window_order(*columns)
      @order_columns = columns.flatten
      self
    end

    def to_window_hash
      options = {}
      options[:partition] = @partition_columns unless @partition_columns.empty?
      options[:order] = @order_columns unless @order_columns.empty?
      options[:as] = @alias_name if @alias_name
      options[:value] = @function_args unless @function_args.empty?
      { @function => options }
    end

    # Materialize the chain into a relation with the window applied
    def to_relation
      @relation.window(to_window_hash)
    end

    # Delegate common relation/query methods so the chain is transparent
    delegate :to_sql, :to_a, :to_ary, :load, :loaded?, :each, :map, :first, :last, :count,
             :where, :select, :joins, :group, :having, :order, :limit, :offset, :reorder, :pluck,
             :find_each, :find_in_batches, :inspect, :exists?, :any?, :none?, :empty?,
             to: :to_relation
  end

  module QueryMethods
    VALID_WINDOW_OPTIONS = %i[value partition order frame as].freeze

    # Non-mutating: returns a new relation with window function projections
    def window(*args)
      raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if args.empty?

      processed = process_window_args(args)
      arel_nodes = processed.map { |name, options| build_window_function(name, options || {}) }

      result = spawn
      # Ensure we keep all columns alongside the window function columns
      result = result.select(klass.arel_table[Arel.star]) if result.select_values.empty?
      result.select(*arel_nodes)
    end

    # Ranking window functions
    def row_number
      WindowChain.new(:row_number, spawn)
    end

    def rank
      WindowChain.new(:rank, spawn)
    end

    def dense_rank
      WindowChain.new(:dense_rank, spawn)
    end

    def percent_rank
      WindowChain.new(:percent_rank, spawn)
    end

    def cume_dist
      WindowChain.new(:cume_dist, spawn)
    end

    def ntile(num_buckets)
      WindowChain.new(:ntile, spawn, function_args: [num_buckets.to_s])
    end

    # Value window functions
    def lag(column, offset = 1, default = nil)
      args = [column.to_s, offset.to_s]
      args << default.to_s unless default.nil?
      WindowChain.new(:lag, spawn, function_args: args)
    end

    def lead(column, offset = 1, default = nil)
      args = [column.to_s, offset.to_s]
      args << default.to_s unless default.nil?
      WindowChain.new(:lead, spawn, function_args: args)
    end

    def first_value(column)
      WindowChain.new(:first_value, spawn, function_args: [column.to_s])
    end

    def last_value(column)
      WindowChain.new(:last_value, spawn, function_args: [column.to_s])
    end

    def nth_value(column, n)
      WindowChain.new(:nth_value, spawn, function_args: [column.to_s, n.to_s])
    end

    # Aggregate window functions
    def window_sum(column)
      WindowChain.new(:sum, spawn, function_args: [column.to_s])
    end

    def window_avg(column)
      WindowChain.new(:avg, spawn, function_args: [column.to_s])
    end

    def window_count(column = "*")
      WindowChain.new(:count, spawn, function_args: [column.to_s])
    end

    def window_min(column)
      WindowChain.new(:min, spawn, function_args: [column.to_s])
    end

    def window_max(column)
      WindowChain.new(:max, spawn, function_args: [column.to_s])
    end

    private

    def build_window_function(name, options)
      window = Arel::Nodes::Window.new

      apply_window_partition(window, options[:partition])
      apply_window_order(window, options[:order])
      apply_window_frame(window, options[:frame]) if options[:frame]

      expressions = extract_window_value(options[:value])

      alias_name = klass.connection.quote_column_name((options[:as] || name).to_s)

      Arel::Nodes::NamedFunction.new(
        name.to_s.upcase,
        expressions
      ).over(window).as(alias_name)
    end

    def apply_window_partition(window, partition)
      return unless partition

      columns = Array(partition)
      return if columns.empty?

      window.partition(columns.map { |p| arel_column(p) })
    end

    def apply_window_order(window, order)
      return unless order

      # When order is a Hash like { salary: :desc }, pass it directly to arel_order
      if order.is_a?(Hash)
        window.order(*arel_order(order))
        return
      end

      columns = Array(order)
      return if columns.empty?

      window.order(*columns.flat_map { |o| arel_order(o) })
    end

    def apply_window_frame(window, frame)
      return unless frame.is_a?(String)

      window.frame(Arel.sql(frame))
    end

    def extract_window_value(value)
      case value
      when Symbol, String
        [Arel::Nodes::SqlLiteral.new(value.to_s)]
      when nil
        []
      when Array
        value.map { |v| Arel::Nodes::SqlLiteral.new(v.to_s) }
      else
        raise ArgumentError, "Invalid argument for window value: #{value.class}"
      end
    end

    def arel_column(name)
      if name.is_a?(Arel::Nodes::Node) || name.is_a?(Arel::Nodes::SqlLiteral)
        name
      else
        klass.arel_table[name.to_sym]
      end
    end

    def arel_order(expr)
      case expr
      when Arel::Nodes::Node, Arel::Nodes::SqlLiteral
        [expr]
      when Hash
        expr.map do |col, dir|
          node = arel_column(col)
          dir.to_s.downcase == "desc" ? node.desc : node.asc
        end
      else
        [arel_column(expr)]
      end
    end

    def process_window_args(args)
      args.flat_map do |element|
        case element
        when Hash
          element.each_value do |v|
            next unless v.is_a?(Hash)

            unsupported = v.keys - VALID_WINDOW_OPTIONS
            raise ArgumentError, "Unsupported window options: #{unsupported.join(', ')}" unless unsupported.empty?
          end
          element.map { |k, v| [k, v] }
        when WindowChain
          [element.to_window_hash.first]
        else
          raise ArgumentError, "Expected Hash or WindowChain, got #{element.class}"
        end
      end
    end
  end
end
