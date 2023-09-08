# ActiveRecordQueryCounter

![Continuous Integration](https://github.com/bdurand/active_record_query_counter/workflows/Continuous%20Integration/badge.svg)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

This gem injects itself into ActiveRecord to give you insight into how your code is using the database. It counts the number of queries, the number of rows returned, the amount of time spent on queries, the number of transactions, and the amount of time spent inside transactions within a block.

The intended use is to gather instrumentation stats for finding hot spots in your code that produce a lot of queries or slow queries or queries that return a lot of rows. It can also be used to find code that is not using transactions when making multiple updates to the database.

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

### Notifications

You can also subscribe to ActiveSupport notifications to get notified when query thresholds are exceeded.

Thresholds are set using class attributes on `ActiveRecordQueryCounter`. By default none of the thresholds are set and no notifications will be sent.

- `query_time_threshold` - Queries that take over this time will trigger a `active_record_query_counter.query_time` notification.
- `row_count_threshold` - Queries that return more than this number of rows will trigger a `active_record_query_counter.row_count` notification.
- `transaction_time_threshold` - Transactions that take over this time will trigger a `active_record_query_counter.transaction_time` notification.
- `transaction_count_threshold` - Blocks that contain more than this number of transactions will trigger a `active_record_query_counter.transaction_count` notification.

The notifications payloads will contain details about the query or transaction that triggered the notification. The payload keys are:

- `active_record_query_counter.query_time` - `:sql`, `:binds`, `:trace`
- `active_record_query_counter.row_count` - `:sql`, `:binds`, `:row_count`, `:trace`
- `active_record_query_counter.transaction_time` - `:trace`
- `active_record_query_counter.transaction_count` - `:transaction_count`, `:trace`

The `:trace` payload is the stack trace of where the query was executed or transaction completed.

```ruby
ActiveRecordQueryCounter.query_time_threshold = 1.0 # seconds
ActiveSupport::Notifications.subscribe('active_record_query_counter.query_time') do |name, start, finish, id, payload|
  elapsed_time = finish - start
  puts "Query time exceeded (#{elasped_time}s): #{payload[:sql]}"
  puts payload[:trace].join("\n")
end

ActiveRecordQueryCounter.row_count_threshold = 1000
ActiveSupport::Notifications.subscribe('active_record_query_counter.row_count') do |name, start, finish, id, payload|
  elapsed = finish - start
  puts "Row count exceeded (#{payload[:row_count]} rows): #{payload[:sql]}"
  puts payload[:trace].join("\n")
end

ActiveRecordQueryCounter.transaction_time_threshold = 2.0 # seconds
ActiveSupport::Notifications.subscribe('active_record_query_counter.transaction_time') do |name, start, finish, id, payload|
  elapsed_time = finish - start
  puts "Transaction time exceeded (#{elasped_time}s)"
  puts payload[:trace].join("\n")
end

ActiveRecordQueryCounter.transaction_count_threshold = 1
ActiveSupport::Notifications.subscribe('active_record_query_counter.transaction_count') do |name, start, finish, id, payload|
  elapsed_time = finish - start
  puts "Transaction count exceeded (#{payload[:transaction_count] transactions in #{elasped_time}s)"
  puts payload[:trace].join("\n")
end
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
