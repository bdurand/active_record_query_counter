# ActiveRecordQueryCounter

[![Continuous Integration](https://github.com/bdurand/active_record_query_counter/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/active_record_query_counter/actions/workflows/continuous_integration.yml)
[![Regression Test](https://github.com/bdurand/active_record_query_counter/actions/workflows/regression_test.yml/badge.svg)](https://github.com/bdurand/active_record_query_counter/actions/workflows/regression_test.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/active_record_query_counter.svg)](https://badge.fury.io/rb/active_record_query_counter)

This gem injects itself into ActiveRecord to give you insight into how your code is using the database.

Within a block of code, it will count:

- the number of queries
- the number of rows returned
- the amount of time spent on queries
- the number of transactions used
- the amount of time spent inside transactions

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

This gem includes middleware for both Rack and Sidekiq that will enable query counting on web requests and in workers. If you are using Rails with Sidekiq, you can enable both with an initializer.

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

If you want to disable query counting within a block of code, you can use the `disable` method.

```ruby
ActiveRecordQueryCounter.count_queries do
  do_something
  ActiveRecordQueryCounter.disable do
    # Queries will not be counted in this block.
    do_something_else
  end
end
```

### Notifications

You can also subscribe to ActiveSupport notifications to get notified when query thresholds are exceeded.

#### active_record_query_counter.query_time notification

This notification is triggered when a query takes longer than the `query_time` threshold. The payload contains the following keys:

- `:sql` - The SQL statement that was executed.
- `:binds` - The bind parameters that were used.
- `:row_count` - The number of rows returned.
- `:trace` - The stack trace of where the query was executed.

#### active_record_query_counter.row_count notification

This notification is triggered when a query returns more rows than the `row_count` threshold. The payload contains the following keys:

- `:sql` - The SQL statement that was executed.
- `:binds` - The bind parameters that were used.
- `:row_count` - The number of rows returned.
- `:trace` - The stack trace of where the query was executed.

#### active_record_query_counter.transaction_time notification

This notification is triggered when a transaction takes longer than the `transaction_time` threshold. The payload contains the following keys:

- `:trace` - The stack trace of where the transaction was completed.

#### active_record_query_counter.transaction_count notification

This notification is triggered when a transaction takes longer than the `transaction_count` threshold. The payload contains the following keys:

- `:transactions` - An array of `ActiveRecordQueryCounter::TransactionInfo` objects.

The duration of the notification event is the time between when the first transaction was started and the last transaction was completed.

#### Thresholds

The thresholds for triggering notifications can be set globally in an initializer:

```ruby
ActiveRecordQueryCounter.default_thresholds.set(
  query_time: 2.0,
  row_count: 1000,
  transaction_time: 5.0,
  transaction_count: 2
)
```

They can be set locally inside a `count_queries` block with the `thresholds` object. Local thresholds will override the global thresholds only inside the block and will not change any global state.

```ruby
ActiveRecordQueryCounter.count_queries do
  ActiveRecordQueryCounter.thresholds.set(
    query_time: 1.0,
    row_count: 100,
    transaction_time: 2.0,
    transaction_count: 1
  )
end
```

You can pass thresholds to individual Sidekiq workers via the `sidekiq_options` on the worker.

```ruby
class MyWorker
  include Sidekiq::Worker

  sidekiq_options(
    active_record_query_counter: {
      thresholds: {
        query_time: 1.0,
        row_count: 100,
        transaction_time: 2.0,
        transaction_count: 1
      }
    }
  )
  # You can disable thresholds for the worker by setting `thresholds: false`.

  def perform
    do_something
  end
end
```

You can set separate thresholds on the Rack middleware when you install it.

```ruby
Rails.application.config.middleware.use(ActiveRecordQueryCounter::RackMiddleware, thresholds: {
  query_time: 1.0,
  row_count: 100,
  transaction_time: 2.0,
  transaction_count: 1
})
```

#### Example Notification Subscriptions

```ruby
ActiveRecordQueryCounter.default_thresholds.query_time = 1.0
ActiveRecordQueryCounter.default_thresholds.row_count = 1000
ActiveRecordQueryCounter.default_thresholds.transaction_time = 2.0
ActiveRecordQueryCounter.default_thresholds.transaction_count = 1

ActiveSupport::Notifications.subscribe('active_record_query_counter.query_time') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "Query time exceeded (#{event.duration}ms): #{event.payload[:sql]}"
  puts event.payload[:trace].join("\n")
end

ActiveSupport::Notifications.subscribe('active_record_query_counter.row_count') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "Row count exceeded (#{event.payload[:row_count]} rows): #{event.payload[:sql]}"
  puts event.payload[:trace].join("\n")
end

ActiveSupport::Notifications.subscribe('active_record_query_counter.transaction_time') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "Transaction time exceeded (#{event.duration}ms)"
  puts event.payload[:trace].join("\n")
end

ActiveSupport::Notifications.subscribe('active_record_query_counter.transaction_count') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "Transaction count exceeded (#{event.payload[:transactions].size} transactions in #{event.duration}ms)"
  event.payload[:transactions].each do |info|
    puts info.trace.join("\n")
  end
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'active_record_query_counter'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install active_record_query_counter
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
