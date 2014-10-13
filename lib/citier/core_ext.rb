class ActiveRecord::Base

  def self.set_acts_as_citier(citier)
    @acts_as_citier = citier
  end

  def self.acts_as_citier?
    @acts_as_citier || false
  end

  def self.[](column_name)
    arel_table[column_name]
  end

  def is_new_record(state)
    @new_record = state
  end

  def self.create_class_writable(class_reference)  #creation of a new class which inherits from ActiveRecord::Base
    Class.new(ActiveRecord::Base) do
      include Citier::InstanceMethods::ForcedWriters
      # set the name of the table associated to this class
      # this class will be associated to the writable table of the class_reference class
      self.table_name = class_reference.table_name.gsub(/^view_/, '')
      self.serialized_attributes ||= self.class_reference.serialized_attributes.reject { |key, value| self.class_reference.superclass.column_names.include?(key) }
    end
  end
end

def create_citier_view(theclass)  #function for creating views for migrations
  # flush any column info in memory
  # Loops through and stops once we've cleaned up to our root class.
  # We MUST user Writable as that is the place where changes might reside!
  reset_class = theclass::Writable
  until reset_class == ActiveRecord::Base
    citier_debug("Resetting column information on #{reset_class}")
    # http://apidock.com/rails/ActiveRecord/Base/reset_column_information/class
    reset_class.reset_column_information
    reset_class = reset_class.superclass
  end

  self_columns      = theclass::Writable.column_names.select{ |c| c != "id" }
  parent_columns    = theclass.superclass.column_names.select{ |c| c != "id" }
  columns           = parent_columns + self_columns
  self_read_table   = theclass.table_name
  self_write_table  = theclass::Writable.table_name
  parent_read_table = theclass.superclass.table_name
  select_sql        = "SELECT #{parent_read_table}.id, #{columns.map { |c| theclass.connection.quote_column_name(c) }.join(',')} FROM #{parent_read_table}, #{self_write_table} WHERE #{parent_read_table}.id = #{self_write_table}.id"
  sql               = "CREATE VIEW #{self_read_table} AS #{select_sql}"
  
  #Use our rails_sql_views gem to create the view so we get it outputted to schema
  create_view "#{self_read_table}", select_sql do |v|
    v.column :id
    columns.each do |c|
      v.column c.to_sym
    end
  end

  citier_debug("Creating citier view -> #{sql}")
  #theclass.connection.execute sql
end

def drop_citier_view(theclass) #function for dropping views for migrations
  self_read_table = theclass.table_name
  sql = "DROP VIEW #{self_read_table}"

  drop_view(self_read_table.to_sym) #drop using our rails sql views gem

  citier_debug("Dropping citier view -> #{sql}")
  #theclass.connection.execute sql
end

def update_citier_view(theclass) #function for updating views for migrations

  citier_debug("Updating citier view for #{theclass}")

  if theclass.table_exists?
    drop_citier_view(theclass)
    create_citier_view(theclass)
  else
    citier_debug("Error: #{theclass} VIEW doesn't exist.")
  end

end

def create_or_update_citier_view(theclass) #Convienience function for updating or creating views for migrations

  citier_debug("Create or Update citier view for #{theclass}")

  if theclass.table_exists?
    update_citier_view(theclass)
  else
    citier_debug("VIEW DIDN'T EXIST. Now creating for #{theclass}")
    create_citier_view(theclass)
  end

end
