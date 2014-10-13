module Citier
  module InstanceMethods
    def self.included(base)
      ActiveRecord::Base.send :include, ForcedWriters
    end
    
    module ForcedWriters
      def or_attributes(new_attributes)
        new_attributes.each {|k,v| @attributes[k] = v if @attributes[k].nil?}
      end
      
      def force_attributes(new_attributes, options = {})
        new_attributes = @attributes.merge(new_attributes) if options[:merge]
        @attributes = new_attributes
        
        if options[:clear_caches] != false
          @aggregation_cache = {}
          @association_cache = {}
          @attributes_cache = {}
        end
      end
    
      def force_changed_attributes(new_changed_attributes, options = {})
        new_changed_attributes = @attributes.merge(new_changed_attributes) if options[:merge]
        @changed_attributes = new_changed_attributes
      end
    end
  
    # USAGE validates :attribute, :citier_uniqueness => true
    # Needed because validates :attribute, :uniqueness => true  Won't work because it tries to call child_class.attribute on parents table
    class CitierUniquenessValidator < ActiveModel::EachValidator  
      def validate_each(object, attribute, value)
        existing_record = object.class.where(attribute.to_sym => value).limit(1).first
        if existing_record && existing_record.as_root != object.as_root #if prev record exist and it isn't our current obj
          object.errors[attribute] << (options[:message] || "has already been taken.")
        end 
      end  
    end

  end
end