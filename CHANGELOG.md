# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.1.0

### Added

- Added count of queries that hit the query cache instead of being sent to the database.

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
