# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.0.0

### Changed

- Calculate elapsed time using monotonic time rather than wall clock time.
- Added method to get the amount of time a single transaction could have taken if it was used to wrap multiple updates.
- Breaking change: transaction information is now returned in a `ActiveRecordQueryCounter::TransactionInfo` objects rather than as a hash of arrays.

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
