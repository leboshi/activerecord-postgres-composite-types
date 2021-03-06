# Extends AR to add composite types functionality.

require 'active_record/connection_adapters/postgresql_adapter'
require 'activerecord-postgres-composite-types/composite_type_parser'

module ActiveRecord

  module ConnectionAdapters

    class PostgreSQLAdapter

      class << self
        def register_composite_type_class(klass)
          self.composite_type_classes[klass.type] = klass
          TableDefinition.register_composite_type klass.type
          Table.register_composite_type klass.type
          register_oid_type klass
        end

        # removes composite types definition (for testing)
        def unregister_composite_types(*composite_types)
          composite_types.each { |type| unregister_composite_type type }
        end

        # removes composite type definition (for testing)
        def unregister_composite_type(type)
          self.composite_type_classes.delete(type.to_sym)
          TableDefinition.unregister_composite_type type
          Table.unregister_composite_type type
        end

        def composite_type_classes
          @composite_type_classes ||= {}
        end
      end
    end

    class PostgreSQLColumn < Column
      # Adds composite type for the column.

      def composite_type_class
        PostgreSQLAdapter.composite_type_classes[type]
      end

      def klass_with_composite_types
        composite_type_klass = PostgreSQLAdapter.composite_type_classes[type]
        composite_type_klass || klass_without_composite_types
      end

      alias_method_chain :klass, :composite_types

      def self.string_to_composite_type(klass, string)
        return string unless String === string
        if string.present?
          fields = CompositeTypeParser.parse_data(string).map.with_index { |val, i| type_cast_composite_type_field(klass, i, val) }
          klass.new(fields)
        end
      end

      def self.type_cast_composite_type_field(klass, i, value)
        klass.initialize_column_definition

        column = klass.columns[i]
        raise "Invalid column index: #{i}" unless column

        cv = column.type_cast_from_database(value)
        if cv.is_a?(String)
          # unquote
          cv = cv.upcase == 'NULL' ? nil : cv.gsub(/\A"(.*)"\Z/m) { $1.gsub(/\\(.)/, '\1') }
        end
        cv
      end

      unless method_defined?(:type_cast_from_database) # AR ver < 4.2
				alias_method :type_cast_from_database, :type_cast
      end

      private

       if private_method_defined?(:simplified_type) # up to v4.1
 	      def simplified_type_with_composite_types(field_type)
 	        type = field_type.to_sym
 	        if PostgreSQLAdapter.composite_type_classes.has_key?(type)
 	          type
 	        else
 	          simplified_type_without_composite_types(field_type)
 	        end
 	      end

 	      alias_method_chain :simplified_type, :composite_types
       end
    end

    class << TableDefinition
      # Adds composite type for migrations. So you can add columns to a table like:
      #   create_table :people do |t|
      #     ...
      #     t.composite_type :composite_value
      #     ...
      #   end
      def register_composite_type(composite_type)
        class_eval <<-RUBY
          def #{composite_type}(*args)
            options = args.extract_options!
            column_names = args
            column_names.each { |name| column(name, '#{composite_type}', options) }
          end
        RUBY
      end

      # Removes composite types from migrations (for testing)
      def unregister_composite_type(composite_type)
        remove_method composite_type
      end
    end

    class << Table

      # Adds composite type for migrations. So you can add columns to a table like:
      #   change_table :people do |t|
      #     ...
      #     t.composite_type :composite_value
      #     ...
      #   end
      def register_composite_type(composite_type)
        class_eval <<-RUBY
					def #{composite_type}(*args)
						options = args.extract_options!
						column_names = args
						column_names.each { |name| column(name, '#{composite_type}', options) }
					end
        RUBY
      end

      # Removes composite types from migrations (for testing)
      def unregister_composite_type(composite_type)
        remove_method composite_type
      end

    end

  end

end

begin
	require_relative "active_record_#{ActiveRecord::VERSION::STRING[0..2].sub('.', '_')}"
rescue LoadError
	raise "Unsupported ActiveRecord version: #{ActiveRecord::VERSION::STRING}"
end
