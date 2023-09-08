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

#### active_record_query_counter.query_time notification

This notification is triggered when a query takes longer than the `query_time` threshold. The payload contains the following keys:

- `:sql` - The SQL statement that was executed.
- `:binds` - The bind parameters that were used.
- `:trace` - The stack trace of where the query was executed.

#### active_record_query_counter.row_count notification

This notification is triggered when a query returns more rows than the `row_count` threshold. The payload contains the following keys:

- `:sql` - The SQL statement that was executed.
- `:binds` - The bind parameters that were used.
- `:row_count` - The number of rows returned.
- `:trace` - The stack trace of where the query was executed.

#### active_record_query_counter.transaction_time notification

This notification is triggered when a transaction takes longer than the `transaction_time` threshold. The payload contains the following keys:

- `:trace` - The stack trace of where the transaction was committed.

#### active_record_query_counter.transaction_count notification

This notification is triggered when a transaction takes longer than the `transaction_count` threshold. The payload contains the following keys:

- `:transactions` - An array of `ActiveRecordQueryCounter::TransactionInfo` objects.

The duration of the notification event is the time between with the first transaction was started and the last transaction was completed.

#### Thresholds

The thresholds for triggering notifications can be set globally:

```ruby
ActiveRecordQueryCounter.default_thresholds.query_time = 2.0
ActiveRecordQueryCounter.default_thresholds.row_count = 1000
ActiveRecordQueryCounter.default_thresholds.transaction_time = 5.0
ActiveRecordQueryCounter.default_thresholds.transaction_count = 2
```

They can be set locally inside a `count_queries` block. The local thresholds will override the global thresholds only inside the block.

```ruby
ActiveRecordQueryCounter.count_queries do
  ActiveRecordQueryCounter.thresholds.query_time = 1.0
  ActiveRecordQueryCounter.thresholds.row_count = 100
  ActiveRecordQueryCounter.thresholds.transaction_time = 2.0
  ActiveRecordQueryCounter.thresholds.transaction_count = 1
end
```

#### Example

```ruby
ActiveRecordQueryCounter.default_thresholds.query_time = 1.0
ActiveRecordQueryCounter.default_thresholds.row_count = 1000
ActiveRecordQueryCounter.default_thresholds.transaction_time = 2.0
ActiveRecordQueryCounter.default_thresholds.transaction_count = 1

ActiveSupport::Notifications.subscribe('active_record_query_counter.query_time') do |name, start, finish, id, payload|
  elapsed_time = finish - start
  puts "Query time exceeded (#{elasped_time}s): #{payload[:sql]}"
  puts payload[:trace].join("\n")
end

ActiveSupport::Notifications.subscribe('active_record_query_counter.row_count') do |name, start, finish, id, payload|
  elapsed = finish - start
  puts "Row count exceeded (#{payload[:row_count]} rows): #{payload[:sql]}"
  puts payload[:trace].join("\n")
end

ActiveSupport::Notifications.subscribe('active_record_query_counter.transaction_time') do |name, start, finish, id, payload|
  elapsed_time = finish - start
  puts "Transaction time exceeded (#{elasped_time}s)"
  puts payload[:trace].join("\n")
end

ActiveSupport::Notifications.subscribe('active_record_query_counter.transaction_count') do |name, start, finish, id, payload|
  elapsed_time = finish - start
  puts "Transaction count exceeded (#{payload[:transactions].size} transactions in #{elasped_time}s)"
  payload[:transactions].each do |info|
    puts info.trace.join("\n")
  end
end
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
