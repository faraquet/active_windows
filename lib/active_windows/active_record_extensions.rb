require "active_record/relation/query_methods"

module ActiveWindows
  module ActiveRecordExtensions

    ::ActiveRecord::QueryMethods.class_eval do
      module Window
        def build_select(arel)
          super

          arel.project(window_values) unless window_values.empty?
        end

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
          # :nodoc:
          self.window_values |= args.map do |name, options|
            build_window_function(name, options || {})
          end

          self
        end

        def build_window_function(name, options)
          # :nodoc:
          window = Arel::Nodes::Window.new

          apply_window_partition(window, options[:partition])
          apply_window_order(window, options[:order])
          apply_window_frame(window, options[:frame]) if options[:frame]

          expressions = extract_window_value(options[:value])

          Arel::Nodes::NamedFunction.new(name.to_s, expressions).over(window).as((options[:as] || name).to_s)
        end

        def apply_window_partition(window, partition)
          # :nodoc:
          return unless partition

          unless partition.is_a?(Symbol) || partition.is_a?(String) || partition.is_a?(Array)
            raise ArgumentError, "Invalid argument for window partition"
          end

          window.partition(Array(partition).map { |p| Arel.sql(p.to_s) })
        end

        def apply_window_order(window, order)
          # :nodoc:
          return unless order

          order_options = prepare_window_order_args(order)
          window.order(order_options)
        end

        def apply_window_frame(window, frame_options)
          # frame = Arel::Nodes::Window::Frame.new(frame_options[:range] || :rows)
          # frame.exclusions = frame_options[:exclusions] if frame_options[:exclusions]
          # frame.start = frame_options[:start] if frame_options[:start]
          # frame.end = frame_options[:end] if frame_options[:end]
          window.frame(Arel.sql "RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW")
        end

        def extract_window_value(value)
          # :nodoc:
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

        def prepare_window_order_args(*args)
          # :nodoc:
          check_if_method_has_arguments!(__callee__, args) do
            sanitize_order_arguments(args)
          end
          preprocess_order_args(args)
          args
        end

        VALID_WINDOW_OPTIONS = [:value, :partition, :order, :frame, :as].freeze

        def process_window_args(args)
          # :nodoc:
          args.flat_map do |element|
            if element.is_a?(Hash)
              unsupported_keys = element.values.flat_map(&:keys) - VALID_WINDOW_OPTIONS
              unless unsupported_keys.empty?
                raise ArgumentError, "Unsupported options: #{unsupported_keys.join(', ')}"
              end

              element.map { |k, v| [k, v] }
            else
              [element]
            end
          end
        end
      end
      prepend Window
    end
  end
end
