module Citier
  module ChildInstanceMethods

    def save(options={})
      return false if (options[:validate] != false && !self.valid?)

      #citier_debug("Callback (#{self.inspect})")
      citier_debug("SAVING #{self.class.to_s}")

      #AIT NOTE: Will change any protected values back to original values so any models onwards won't see changes.
      # Run save and create/update callbacks, just like ActiveRecord does
      self.run_callbacks(:save) do
        self.run_callbacks(self.new_record? ? :create : :update) do
          #get the attributes of the class which are inherited from it's parent.
          attributes = self.instance_variable_get(:@attributes)
          changed_attributes = self.instance_variable_get(:@changed_attributes)
          attributes_for_parent = attributes.reject { |key,value| !self.class.superclass.column_names.include?(key) }
          changed_attributes_for_parent = changed_attributes.reject { |key,value| !self.class.superclass.column_names.include?(key) }

          # Get the attributes of the class which are unique to this class and not inherited.
          attributes_for_current = attributes.reject { |key,value| self.class.superclass.column_names.include?(key) }
          changed_attributes_for_current = changed_attributes.reject { |key,value| self.class.superclass.column_names.include?(key) }

          citier_debug("Attributes for #{self.class.superclass.to_s}: #{attributes_for_parent.inspect}")
          citier_debug("Changed attributes for #{self.class.superclass.to_s}: #{changed_attributes_for_parent.keys.inspect}")
          citier_debug("Attributes for #{self.class.to_s}: #{attributes_for_current.inspect}")
          citier_debug("Changed attributes for #{self.class.to_s}: #{changed_attributes_for_current.keys.inspect}")

          ########
          #
          # Parent saving

          #create a new instance of the superclass, passing the inherited attributes.
          parent = self.class.superclass.new

          parent.force_attributes(attributes_for_parent, :merge => true)
          changed_attributes_for_parent["id"] = 0 # We need to change at least something to force a timestamps update.
          parent.force_changed_attributes(changed_attributes_for_parent)

          parent.id = self.id if id
          parent.type = self.type

          parent.is_new_record(new_record?)

          # If we're root (AR subclass) this will just be saved as normal through AR. If we're a child it will call this method again.
          # It will try and save it's parent and then save itself through the Writable constant.
          parent.transaction do
            parent_saved = parent.save
            self.id = parent.id
            self.created_at ||= parent.created_at  # should set the generated timestamps to view object
            self.updated_at ||= parent.updated_at

            if !parent_saved
              # Couldn't save parent class
              citier_debug("Class (#{self.class.superclass.to_s}) could not be saved")
              citier_debug("Errors = #{parent.errors.to_s}")
              return false # Return false and exit run_callbacks :save and :create/:update, so the after_ callback won't run.
            end

            #End of parent saving

            ######
            ##
            ## Self Saving
            ##

            # If there are attributes for the current class (unique & not inherited), save current model
            if !attributes_for_current.empty?
              current = self.class::Writable.new

              current.force_attributes(attributes_for_current, :merge => true)
              current.force_changed_attributes(changed_attributes_for_current)

              current.id = self.id
              current.is_new_record(new_record?)

              current_saved = current.save

              current.after_save_change_request if current.respond_to?('after_save_change_request') #Specific to an app I'm building

              if !current_saved
                citier_debug("Class (#{self.class.superclass.to_s}) could not be saved")
                citier_debug("Errors = #{current.errors.to_s}")
                return false # Return false and exit run_callbacks :save and :create/:update, so the after callback won't run.
              end
            end

            # at this point, parent_saved && current_saved

            is_new_record(false) # This is no longer a new record

            self.force_changed_attributes({}) # Reset changed_attributes so future changes will be tracked correctly

            # No return, because we want the after callback to run.
          end
        end
      end
      return true
    end

    def save!(options={})
      raise ActiveRecord::RecordInvalid.new(self) if (options[:validate] != false && !self.valid?)
      self.save || raise(ActiveRecord::RecordNotSaved)
    end

    include InstanceMethods
  end
end
