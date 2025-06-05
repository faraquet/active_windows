require "active_record"

module ActiveWindows
  module ActiveRecordExtensions
    extend ActiveSupport::Concern

    module Window
      class WindowChain
        attr_reader :function, :alias_name, :partition_columns, :order_columns

        def initialize(function)
          @function = function
          @alias_name = nil
          @partition_columns = []
          @order_columns = []
        end

        def as(name)
          @alias_name = name
          self
        end

        def partition_by(*columns)
          @partition_columns = columns
          self
        end

        def order(*columns)
          @order_columns = columns
          self
        end
      end

      def row_number
        WindowChain.new(:row_number)
      end

      def window(*args)
        args = process_window_args(args)
        spawn.window!(*args)
      end

      def window!(*args)
        # Initialize window_values if it doesn't exist
        self.window_values ||= []

        self.window_values |= args.map do |name, options|
          build_window_function(name, options || {})
        end

        self
      end

      # Add window_values accessor
      def window_values
        @window_values ||= []
      end

      def window_values=(value)
        @window_values = value
      end

      def build_window_function(name, options)
        window = Arel::Nodes::Window.new

        apply_window_partition(window, options[:partition])
        apply_window_order(window, options[:order])
        apply_window_frame(window, options[:frame]) if options[:frame]

        expressions = extract_window_value(options[:value])

        Arel::Nodes::NamedFunction.new(name.to_s, expressions).over(window).as((options[:as] || name).to_s)
      end

      def apply_window_partition(window, partition)
        return unless partition

        unless partition.is_a?(Symbol) || partition.is_a?(String) || partition.is_a?(Array)
          raise ArgumentError, "Invalid argument for window partition"
        end

        window.partition(Array(partition).map { |p| Arel.sql(p.to_s) })
      end

      def apply_window_order(window, order)
        return unless order

        order_options = prepare_window_order_args(order)
        window.order(*order_options)  # Use splat operator
      end

      def apply_window_frame(window, frame_options)
        window.frame(Arel.sql("RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW"))
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
          raise ArgumentError, "Invalid argument for window value"
        end
      end

      def prepare_window_order_args(order)
        # Simplified version - just return the order as an array
        Array(order).map { |o| Arel.sql(o.to_s) }
      end

      VALID_WINDOW_OPTIONS = [:value, :partition, :order, :frame, :as].freeze

      def process_window_args(args)
        args.flat_map do |element|
          if element.is_a?(Hash)
            element.each do |k, v|
              if v.is_a?(Hash)
                unsupported_keys = v.keys - VALID_WINDOW_OPTIONS
                unless unsupported_keys.empty?
                  raise ArgumentError, "Unsupported options: #{unsupported_keys.join(', ')}"
                end
              end
            end

            element.map { |k, v| [k, v] }
          else
            [element]
          end
        end
      end
    end

    included do
      include Window
    end
  end
end
