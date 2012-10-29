module ActiveRecord
  class Relation

    alias_method :relation_delete_all, :delete_all
    def delete_all(conditions = nil)
      return relation_delete_all(conditions) if !@klass.acts_as_citier?

      return relation_delete_all(conditions) if conditions

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

      deleted &= c.base_class.where(where_hash).relation_delete_all
      while c.superclass != ActiveRecord::Base
        if c.const_defined?(:Writable)
          citier_debug("Deleting back up hierarchy #{c}")
          deleted &= c::Writable.where(where_hash).delete_all
        end
        c = c.superclass
      end

      deleted
    end

    alias_method :relation_to_a, :to_a
    def to_a
      return relation_to_a if !@klass.acts_as_citier?

      records = relation_to_a

      c = @klass

      if records.all? { |record| record.class == c }
        return records
      end

      full_records = []
      ids_wanted = {}

      # Map all the ids wanted per type
      records.each do |record|
        if record.class == c # We don't need to find the record again if this is already the correct one
          full_records << record
          next
        end

        ids_wanted[record.class] ||= []
        ids_wanted[record.class] << record.id
      end

      # Find all wanted records
      ids_wanted.each do |type_class, ids|
        full_records.push(*type_class.find(ids))
      end

      # Make a new array with the found records at the right places
      records.each do |record|
        full_record = full_records.find { |full_record| full_record.id == record.id }
        record.force_attributes(full_record.instance_variable_get(:@attributes), :merge => true, :clear_caches => false)
      end

      return records
    end

    alias_method :relation_apply_finder_options, :apply_finder_options
    def apply_finder_options(options)
      return relation_apply_finder_options(options) if !@klass.acts_as_citier?

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

      relation.relation_apply_finder_options(options)
    end
  end
end
