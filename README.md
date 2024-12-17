# ActiveRecordQueryCounter

[![Continuous Integration](https://github.com/bdurand/active_record_query_counter/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/active_record_query_counter/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/active_record_query_counter.svg)](https://badge.fury.io/rb/active_record_query_counter)

**ActiveRecordQueryCounter** is a ruby gem that provides detailed insights into how your code interacts with the database by hooking into ActiveRecord.

It measures database usage within a block of code, including:

- The number of queries executed
- The number of rows returned
- The total time spent on queries
- The number of transactions used
- The total time spent inside transactions
- The number of transactions that were rolled back

This gem is designed to help you:

- Identify "hot spots" in your code that generate excessive or slow queries.
- Spot queries returning unexpectedly large result sets.
- Detect areas where transactions are underutilized, especially when performing multiple database updates.

## Usage

### Enabling The Gem

To use **ActiveRecordQueryCounter**, you first need to enable it on your database connection adapter. Add the following to an initializer:

For **PostgreSQL**:

```ruby
ActiveRecordQueryCounter.enable!(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
```

For **MySQL**:

```ruby
ActiveRecordQueryCounter.enable!(ActiveRecord::ConnectionAdapters::Mysql2Adapter)
```

### Counting Queries

To measure database activity, wrap the code you want to monitor inside a `count_queries` block:

```ruby
ActiveRecordQueryCounter.count_queries do
  do_something
  puts "Queries: #{ActiveRecordQueryCounter.query_count}"
  puts "Rows: #{ActiveRecordQueryCounter.row_count}"
  puts "Query Time: #{ActiveRecordQueryCounter.query_time}"
  puts "Transactions: #{ActiveRecordQueryCounter.transaction_count}"
  puts "Transaction Time: #{ActiveRecordQueryCounter.transaction_time}"
  puts "Rollbacks: #{ActiveRecordQueryCounter.rollback_count}"
end
```

### Middleware Integration

For **Rails** and **Sidekiq**, middleware is included to enable query counting in web requests and workers.

Add the following to an initializer:

```ruby
ActiveSupport.on_load(:active_record) do
  ActiveRecordQueryCounter.enable!(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
end

# Enable Rack Middleware
Rails.application.config.middleware.use(ActiveRecordQueryCounter::RackMiddleware)

# Enable Sidekiq Middleware
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add ActiveRecordQueryCounter::SidekiqMiddleware
  end
end
```

### Disabling Query Counting

You can temporarily disable query counting within a block using `disable`:

```ruby
ActiveRecordQueryCounter.count_queries do
  do_something
  ActiveRecordQueryCounter.disable do
    # Queries in this block will not be counted.
    do_something_else
  end
end
```

### Notifications

**ActiveRecordQueryCounter** supports ActiveSupport notifications when certain query thresholds are exceeded.

#### Available Notifications

##### 1. active_record_query_counter.query_time notification

Triggered when a query exceeds the query_time threshold with the payload:


- `:sql` - The SQL statement that was executed.
- `:binds` - The bind parameters that were used.
- `:row_count` - The number of rows returned.
- `:trace` - The stack trace of where the query was executed.

##### 2. active_record_query_counter.row_count notification

Triggered when a query exceeds the row_count threshold with the payload:

- `:sql` - The SQL statement that was executed.
- `:binds` - The bind parameters that were used.
- `:row_count` - The number of rows returned.
- `:trace` - The stack trace of where the query was executed.

##### 3. active_record_query_counter.transaction_time notification

Triggered when a transaction exceeds the transaction_time threshold with the payload:

- `:trace` - The stack trace of where the transaction was completed.

##### 4. active_record_query_counter.transaction_count notification

Triggered when transactions exceed the transaction_count threshold with the payload:

- `:transactions` - An array of `ActiveRecordQueryCounter::TransactionInfo` objects.

The duration of the notification event is the time between when the first transaction was started and the last transaction was completed.

#### Setting Thresholds

Thresholds can be configured **globally** in an initializer:

```ruby
ActiveRecordQueryCounter.default_thresholds.set(
  query_time: 2.0,
  row_count: 1000,
  transaction_time: 5.0,
  transaction_count: 2
)
```

Or locally within a block:

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

#### Sidekiq Worker Thresholds
Thresholds for individual Sidekiq workers can be set using `sidekiq_options`:

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

  def perform
    do_something
  end
end
```

To disable thresholds for a worker, set `thresholds: false`.

#### Rack Middleware Thresholds

You can configure separate thresholds for the Rack middleware:

```ruby
Rails.application.config.middleware.use(ActiveRecordQueryCounter::RackMiddleware, thresholds: {
  query_time: 1.0,
  row_count: 100,
  transaction_time: 2.0,
  transaction_count: 1
})
```

#### Example: Subscribing to Notifications

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
