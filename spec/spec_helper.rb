# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])

begin
  require "simplecov"
  SimpleCov.start do
    add_filter ["/spec/", "/app/", "/config/", "/db/"]
  end
rescue LoadError
end

Bundler.require(:default, :test)

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

def capture_notifications(name)
  payloads = []

  subscription = ActiveSupport::Notifications.subscribe("active_record_query_counter.#{name}") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    payloads << event.payload.merge(duration: event.duration)
  end

  yield

  ActiveSupport::Notifications.unsubscribe(subscription)

  payloads
end

RSpec.configure do |config|
  config.order = :random
end
