module Citier
  module ActsAsCitier
    module Relation
      extend ActiveSupport::Concern

      included do
        class_eval do
          alias_method_chain :delete_all, :citier
          alias_method_chain :to_a, :citier
          alias_method_chain :apply_finder_options, :citier
        end
      end

      def delete_all_with_citier(conditions = nil)
        return delete_all_without_citier(conditions) if !@klass.acts_as_citier?
        return delete_all_without_citier(conditions) if conditions

        deleted = true
        ids = nil
        c = @klass

        bind_values.each do |bind_value|
          if bind_value[0].name == "id"
            ids = bind_value[1]
            break
          end
        end
        ids ||= where_values_hash["id"] || where_values_hash[:id]
        if ids.nil?
          arel.projections = [Arel::SqlLiteral.new("#{c.table_name}.id")]
          ids = c.find_by_sql(arel, bind_values).map(&:id)
        end
        where_hash = { :id => ids }

        deleted &= c.base_class.where(where_hash).delete_all_without_citier
        while c.superclass != ActiveRecord::Base
          if c.const_defined?(:Writable)
            citier_debug("Deleting back up hierarchy #{c}")
            deleted &= c::Writable.where(where_hash).delete_all_without_citier
          end
          c = c.superclass
        end

        deleted
      end

      def to_a_with_citier
        records = to_a_without_citier

        return records if !@klass.acts_as_citier?

        c = @klass

        if records.all? { |record| record.class == c }
          return records
        end

        full_records = []
        ids_wanted = {}

        # Map all the ids wanted per type
        records.each do |record|
          if record.class != c # We don't need to find the record again if this is already the correct one
            ids_wanted[record.class] ||= []
            ids_wanted[record.class] << record.id
          end
        end

        # Find all wanted records
        ids_wanted.each do |type_class, ids|
          full_records.push(*type_class.find(ids))
        end

        # Make a new array with the found records at the right places
        records.each do |record|
          if record.class != c
            full_record = full_records.find { |full_record| full_record.id == record.id }
            record.force_attributes(full_record.instance_variable_get(:@attributes), :merge => true, :clear_caches => false)
          end
        end

        return records
      end

      def apply_finder_options_with_citier(options)
        return apply_finder_options_without_citier(options) if !@klass.acts_as_citier?

        relation = self

        # With option :no_children set to true, only records of type self will be returned.
        # So Root.all(:no_children => true) won't return Child records.
        no_children = options.delete(:no_children)
        if no_children
          relation = clone

          c = @klass

          self_type = c.superclass == ActiveRecord::Base ? nil : c.name
          relation = relation.where(:type => self_type)
        end

        relation.apply_finder_options_without_citier(options)
      end
    end
  end
end

ActiveRecord::Relation.send(:include, Citier::ActsAsCitier::Relation)
