# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 3.2.0

### Added

- Connection setup time (time spent in the adapter's `connect!`, `reconnect!`, and `verify!` methods while running a query) is now measured and subtracted from the reported query time, so a query that triggers a reconnect after an idle period or a database failover is no longer reported as an inexplicably slow query. The time is reported separately as `:connection_time` in the `query_time` and `row_count` notification payloads.

### Removed

- Support for ActiveRecord versions prior to 7.1.

## 3.1.1

### Fixed

- Reverted overloaded args syntax in `ConnectionAdapterExtension` that was causing error on methods that added additional keyword arguments.

## 3.1.0

### Changed

- Transaction time now ends when the COMMIT or ROLLBACK statement completes rather than before it is sent, so it includes the commit itself. Time spent in after commit and after rollback callbacks is not included since those run after the database transaction is over.
- The counter is now stored in `ActiveSupport::IsolatedExecutionState` when available (Rails 7+) so that query counting follows the application's configured thread or fiber isolation level. On Rails 6.x the counter remains fiber-local.

### Fixed

- A transaction whose COMMIT statement fails (e.g. a deadlock or serialization failure detected at commit time) is now counted as a rollback. Previously it was recorded as a successful commit and the rollback count was not incremented.
- `ActiveRecordQueryCounter.last_transaction_end_time` now returns the latest transaction end time when transactions on multiple connections overlap. Previously it returned the end time of the transaction that started last.
- Cached queries for ignored statements (`SCHEMA`, `EXPLAIN`) are no longer counted in the cached query count.
- Setting up the query cache subscription in `ActiveRecordQueryCounter.enable!` is now thread safe, so concurrent calls can no longer create duplicate subscriptions that would double count cached queries.

## 3.0.0

### Changed

- Query time now excludes GC pause time and Ruby thread CPU time so that it more closely reflects the time actually spent waiting on the database. This is what is now reported as the event duration in the `query_time` and `row_count` notifications.

### Added

- Added `:elapsed_time` (the raw wall clock time), `:gc_time`, and `:cpu_time` (all in milliseconds) to the `query_time` and `row_count` notification payloads.

### Removed

- Dropped support for Ruby versions older than 3.1 (required for `GC.total_time`).

## 2.3.0

### Added

- Added count of rollbacks from transactions

## 2.2.1

### Changed

- Classes not required to run the gem are now lazy loaded.

## 2.2.0

### Added

- Added `ActiveRecordQueryCounter.disable` method to allow disabling query counting behavior within a block.
- Rails 7.1 compatibility.

## 2.1.0

### Added

- Added count of queries that hit the query cache instead of being sent to the database.

### Removed

- Dropped support for ActiveRecord 5.0.

## 2.0.0

### Added

- Added capability to send ActiveSupport notifications when query thresholds are exceeded.

### Changed

- Calculate elapsed time using monotonic time rather than wall clock time.
- Schema queries to get the table structure and explain plan queries are no longer counted.
- **Breaking change**: transaction information is now returned in an array of `ActiveRecordQueryCounter::TransactionInfo` objects.
- **Breaking change**: internal API for tracking queries and transactions has changed

## 1.1.2

### Added

- Ruby 3.0 compatibility

### Removed

- Dropped support for ActiveRecord 4.2

## 1.1.1
### Added

- Expose stack traces where transactions are being committed.

## 1.1.0
### Added

- Add number of transactions to statistics being tracked.

## 1.0.0
### Added

- Track stats about queries run by ActiveRecord within a block.
