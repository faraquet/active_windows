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

    def order_by(*columns)
      @order_columns = columns.flatten
      self
    end

    def to_window_hash
      options = {}
      options[:partition_by] = @partition_columns unless @partition_columns.empty?
      options[:order_by] = @order_columns unless @order_columns.empty?
      options[:as] = @alias_name if @alias_name
      options[:value] = @function_args unless @function_args.empty?
      { @function => options }
    end

    # Materialize the chain into a relation with the window applied
    def to_relation
      @relation.window(to_window_hash)
    end

    # Delegate to the materialized relation so the chain is transparent.
    # Explicit delegates for Ruby protocol methods that must be defined eagerly.
    delegate :to_sql, :to_a, :to_ary, :inspect, to: :to_relation

    private

    def method_missing(method, ...)
      relation = to_relation
      if relation.respond_to?(method)
        relation.public_send(method, ...)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      to_relation.respond_to?(method, include_private) || super
    end
  end

  module QueryMethods
    VALID_WINDOW_OPTIONS = %i[value partition_by order_by frame as over].freeze

    # Fluent: window(:row_number) returns a WindowChain
    # Fluent with args: window(:lag, :salary, 1, 0) returns a WindowChain
    # Hash: window(row_number: { partition: :department, order_by: :salary, as: :rank })
    def window(*args)
      raise ArgumentError, "wrong number of arguments (given 0, expected 1+)" if args.empty?

      # Fluent API: window(:function_name, *function_args)
      if args.first.is_a?(Symbol) && (args.length == 1 || !args[1].is_a?(Hash))
        function_name = args.shift
        return WindowChain.new(function_name, spawn, function_args: args.map(&:to_s))
      end

      # Hash API
      processed = process_window_args(args)

      result = spawn
      arel_nodes = processed.map { |name, options| build_window_function(name, options || {}) }

      # Ensure we keep all columns alongside the window function columns
      result = result.select(klass.arel_table[Arel.star]) if result.select_values.empty?
      result.select(*arel_nodes)
    end

    private

    def build_window_function(name, options)
      window = Arel::Nodes::Window.new

      apply_window_partition(window, options[:partition_by])
      apply_window_order(window, options[:order_by])
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
        resolve_column(name)
      end
    end

    def resolve_column(name)
      name_sym = name.to_sym
      return klass.arel_table[name_sym] if klass.column_names.include?(name.to_s)

      reflection = klass.reflect_on_association(name_sym)
      if reflection&.macro == :belongs_to
        klass.arel_table[reflection.foreign_key.to_sym]
      else
        klass.arel_table[name_sym]
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
      # First pass: collect named window definitions from define: key
      definitions = {}
      args.each do |element|
        next unless element.is_a?(Hash) && element.key?(:define)

        element[:define].each do |name, opts|
          definitions[name] = opts
        end
      end

      # Second pass: build function list, resolving over: references
      args.flat_map do |element|
        case element
        when Hash
          element.except(:define).map do |k, v|
            next [k, v] unless v.is_a?(Hash)

            # Resolve over: reference to a named window definition
            if v.key?(:over)
              window_name = v[:over]
              definition = definitions[window_name]
              raise ArgumentError, "Unknown window definition: #{window_name}" unless definition

              v = definition.merge(v.except(:over))
            end

            unsupported = v.keys - VALID_WINDOW_OPTIONS
            raise ArgumentError, "Unsupported window options: #{unsupported.join(', ')}" unless unsupported.empty?

            [k, v]
          end.compact
        when WindowChain
          [element.to_window_hash.first]
        else
          raise ArgumentError, "Expected Hash or WindowChain, got #{element.class}"
        end
      end
    end
  end
end
