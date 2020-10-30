# ActiveRecordQueryCounter

[![Build Status](https://travis-ci.org/bdurand/active_record_query_counter.svg?branch=master)](https://travis-ci.org/bdurand/active_record_query_counter)
[![Maintainability](https://api.codeclimate.com/v1/badges/21094ecec0c151983bb1/maintainability)](https://codeclimate.com/github/bdurand/active_record_query_counter/maintainability)

This gem injects itself into ActiveRecord to count the number of queries, the number of rows returned, the amount of time spent on queries, the number of transactions, and the amount of time spent inside transactions within a block.

The intended use is to gather instrumentation stats for finding hot spots in your code.

## Usage

The behavior must be enabled on your database connection adapter from within an initializer.

Postgres:

```ruby
ActiveRecordQueryCounter.enable!(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
```

MySQL:

```ruby
ActiveRecordQueryCounter.enable!(ActiveRecord::ConnectionAdapters::Mysql2Adapter)
```

Next you must specify the blocks where you want to count queries.

```ruby
ActiveRecordQueryCounter.count_queries do
  do_something
  puts "Queries: #{ActiveRecordQueryCounter.query_count}"
  puts "Rows: #{ActiveRecordQueryCounter.row_count}"
  puts "Query Time: #{ActiveRecordQueryCounter.query_time}"
  puts "Transactions: #{ActiveRecordQueryCounter.transaction_count}"
  puts "Transaction Time: #{ActiveRecordQueryCounter.transaction_time}"
end
```

This gem includes middleware for both Rack and Sidekiq that will enable query counting.

If you are using Rails with Sidekiq, you can enable both with an initializer.

```ruby
ActiveSupport.on_load(:active_record) do
  ActiveRecordQueryCounter.enable!(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
end

Rails.application.config.middleware.use(ActiveRecordQueryCounter::RackMiddleware)

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add ActiveRecordQueryCounter::SidekiqMiddleware
  end
end
```
