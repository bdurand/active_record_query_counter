# ActiveRecordQueryCounter

![Continuous Integration](https://github.com/bdurand/active_record_query_counter/workflows/Continuous%20Integration/badge.svg)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

This gem injects itself into ActiveRecord to count the number of queries, the number of rows returned, the amount of time spent on queries, the number of transactions, and the amount of time spent inside transactions within a block.

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

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
