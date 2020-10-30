require "active_record"
require_relative "../lib/active_record_query_counter"

ActiveRecord::Base.establish_connection("adapter" => "sqlite3", "database" => ":memory:")
ActiveRecordQueryCounter.enable!(ActiveRecord::Base.connection.class)

class TestModel < ActiveRecord::Base
  unless table_exists?
    connection.create_table(table_name) do |t|
      t.column :name, :string
    end
  end
end
