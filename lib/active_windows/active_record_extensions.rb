# frozen_string_literal: true

require "active_record"

module ActiveWindows
  class WindowChain
    attr_reader :function, :alias_name, :partition_columns, :order_columns

    def initialize(function, relation)
      @function = function
      @relation = relation
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

    def order(*columns)
      @order_columns = columns.flatten
      self
    end

    def to_window_hash
      options = {}
      options[:partition] = @partition_columns unless @partition_columns.empty?
      options[:order] = @order_columns unless @order_columns.empty?
      options[:as] = @alias_name if @alias_name
      { @function => options }
    end

    # Materialize the chain into a relation with the window applied
    def to_relation
      @relation.window(to_window_hash)
    end

    # Delegate common relation/query methods so the chain is transparent
    delegate :to_sql, :to_a, :to_ary, :load, :loaded?, :each, :map, :first, :last, :count,
             :where, :select, :joins, :group, :having, :limit, :offset, :reorder, :pluck,
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

    def row_number
      WindowChain.new(:row_number, spawn)
    end

    private

    def build_window_function(name, options)
      window = Arel::Nodes::Window.new

      apply_window_partition(window, options[:partition])
      apply_window_order(window, options[:order])
      apply_window_frame(window, options[:frame]) if options[:frame]

      expressions = extract_window_value(options[:value])

      Arel::Nodes::NamedFunction.new(
        name.to_s.upcase,
        expressions
      ).over(window).as((options[:as] || name).to_s)
    end

    def apply_window_partition(window, partition)
      return unless partition

      columns = Array(partition)
      return if columns.empty?

      window.partition(columns.map { |p| arel_column(p) })
    end

    def apply_window_order(window, order)
      return unless order

      columns = Array(order)
      return if columns.empty?

      window.order(*columns.map { |o| arel_column(o) })
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
