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

### Query Time

The query time (`ActiveRecordQueryCounter.query_time` and the duration reported by the notifications) is **not** the raw wall clock time a query took. The wall clock time includes time the thread was not actually waiting on the database, such as GC pauses (which can be triggered by other threads and stop the world), the Ruby CPU work of building the result objects, and the time spent establishing or re-establishing the database connection. On a busy, multi-threaded server these can add up to seconds, making a trivial query look pathologically slow.

To report the time actually spent waiting on the database as closely as possible, the connection setup time, GC time, and thread CPU time that elapsed while the query ran are subtracted from the wall clock time. The raw wall clock time is still available as `:elapsed_time` in the notification payloads.

Connection setup time is the wall clock time spent inside the adapter's `connect!`, `reconnect!`, and `verify!` methods while running the query. ActiveRecord (re)establishes and verifies connections lazily, from within the query execution path, so when a connection has gone stale — after an idle period, or a database failover (common with clustered databases such as Amazon Aurora) — the reconnect (DNS resolution, TCP connect, TLS handshake, and authentication) happens on the next query and is otherwise charged to it. This is reported separately as `:connection_time` in the notification payloads so these events are diagnosable rather than appearing as inexplicably slow queries.

> [!NOTE]
> Measuring GC time requires Ruby's GC total time measurement, which is enabled by default (`GC.measure_total_time`). Thread CPU time is measured via `Process::CLOCK_THREAD_CPUTIME_ID`; on platforms that do not provide it, CPU time is treated as zero.

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
- `:elapsed_time` - The raw wall clock time the query took (in milliseconds).
- `:gc_time` - The GC time that elapsed while the query ran (in milliseconds).
- `:cpu_time` - The thread CPU time spent while the query ran (in milliseconds).
- `:connection_time` - The time spent establishing, verifying, or reconnecting the database connection while the query ran (in milliseconds).

The duration of the notification event is the query time: the wall clock time with the connection setup time, GC time, and CPU time subtracted out (see [Query Time](#query-time)). The raw wall clock time is still available as `:elapsed_time`.

##### 2. active_record_query_counter.row_count notification

Triggered when a query exceeds the row_count threshold with the payload:

- `:sql` - The SQL statement that was executed.
- `:binds` - The bind parameters that were used.
- `:row_count` - The number of rows returned.
- `:trace` - The stack trace of where the query was executed.
- `:elapsed_time` - The raw wall clock time the query took (in milliseconds).
- `:gc_time` - The GC time that elapsed while the query ran (in milliseconds).
- `:cpu_time` - The thread CPU time spent while the query ran (in milliseconds).
- `:connection_time` - The time spent establishing, verifying, or reconnecting the database connection while the query ran (in milliseconds).

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
