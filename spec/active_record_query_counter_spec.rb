require "spec_helper"

describe ActiveRecordQueryCounter do
  before :each do
    TestModel.create!(name: "A")
    TestModel.create!(name: "B")
    TestModel.create!(name: "C")
  end

  after :each do
    TestModel.destroy_all
  end

  describe "counting queries" do
    it "is not enabled outside of a count_queries block" do
      result = TestModel.all.to_a
      expect(result.map(&:name)).to match_array(["A", "B", "C"])
      expect(ActiveRecordQueryCounter.query_count).to eq nil
      expect(ActiveRecordQueryCounter.row_count).to eq nil
      expect(ActiveRecordQueryCounter.query_time).to eq nil
      expect(ActiveRecordQueryCounter.cached_query_count).to eq nil
      expect(ActiveRecordQueryCounter.transaction_count).to eq nil
      expect(ActiveRecordQueryCounter.transactions).to eq nil
      expect(ActiveRecordQueryCounter.transaction_time).to eq nil
      expect(ActiveRecordQueryCounter.info).to eq nil
    end

    it "returns empty information when no queries have been made" do
      ActiveRecordQueryCounter.count_queries do
        expect(ActiveRecordQueryCounter.query_count).to eq 0
        expect(ActiveRecordQueryCounter.row_count).to eq 0
        expect(ActiveRecordQueryCounter.query_time).to eq 0
        expect(ActiveRecordQueryCounter.cached_query_count).to eq 0
        expect(ActiveRecordQueryCounter.transaction_count).to eq 0
        expect(ActiveRecordQueryCounter.transactions).to eq []
        expect(ActiveRecordQueryCounter.transaction_time).to eq 0
        expect(ActiveRecordQueryCounter.info).to eq({
          query_count: 0,
          row_count: 0,
          query_time: 0,
          cached_query_count: 0,
          cache_hit_rate: 0.0,
          transaction_count: 0,
          transaction_time: 0,
          rollback_count: 0
        })
      end
    end

    it "counts the number of queries and rows returned within a block" do
      ActiveRecordQueryCounter.count_queries do
        result = TestModel.all.to_a
        expect(result.map(&:name)).to match_array(["A", "B", "C"])
        expect(ActiveRecordQueryCounter.query_count).to eq 1
        expect(ActiveRecordQueryCounter.row_count).to eq 3

        result = TestModel.find_by(name: "B")
        expect(result.name).to eq "B"
        expect(ActiveRecordQueryCounter.query_count).to eq 2
        expect(ActiveRecordQueryCounter.row_count).to eq 4

        expect(ActiveRecordQueryCounter.query_time).to be_a(Float)
        expect(ActiveRecordQueryCounter.query_time).to be >= 0

        ActiveRecord::Base.transaction { true }

        expect(ActiveRecordQueryCounter.info).to eq({
          query_count: 2,
          row_count: 4,
          query_time: ActiveRecordQueryCounter.query_time,
          cached_query_count: 0,
          cache_hit_rate: 0.0,
          transaction_count: 1,
          transaction_time: ActiveRecordQueryCounter.transaction_time,
          rollback_count: 0
        })
      end

      expect(ActiveRecordQueryCounter.query_count).to eq nil
      expect(ActiveRecordQueryCounter.row_count).to eq nil
      expect(ActiveRecordQueryCounter.query_time).to eq nil
      expect(ActiveRecordQueryCounter.info).to eq nil
    end

    it "does not count cached queries" do
      ActiveRecord::Base.cache do
        ActiveRecordQueryCounter.count_queries do
          result = TestModel.find_by(name: "B")
          expect(result.name).to eq "B"
          expect(ActiveRecordQueryCounter.query_count).to eq 1
          expect(ActiveRecordQueryCounter.row_count).to eq 1
          expect(ActiveRecordQueryCounter.cached_query_count).to eq 0

          result = TestModel.find_by(name: "B")
          expect(result.name).to eq "B"
          expect(ActiveRecordQueryCounter.query_count).to eq 1
          expect(ActiveRecordQueryCounter.row_count).to eq 1
          expect(ActiveRecordQueryCounter.cached_query_count).to eq 1

          expect(ActiveRecordQueryCounter.info).to eq({
            query_count: 1,
            row_count: 1,
            query_time: ActiveRecordQueryCounter.query_time,
            cached_query_count: 1,
            cache_hit_rate: 0.5,
            transaction_count: 0,
            transaction_time: 0,
            rollback_count: 0
          })
        end
      end
    end

    it "counts queries with no results" do
      ActiveRecordQueryCounter.count_queries do
        result = TestModel.find_by(name: "X")
        expect(result).to eq nil
        expect(ActiveRecordQueryCounter.query_count).to eq 1
        expect(ActiveRecordQueryCounter.row_count).to eq 0
      end
    end

    it "counts aggregates" do
      ActiveRecordQueryCounter.count_queries do
        result = TestModel.count
        expect(result).to eq 3
        expect(ActiveRecordQueryCounter.query_count).to eq 1
        expect(ActiveRecordQueryCounter.row_count).to eq 1
      end
    end
  end

  describe "counting transactions" do
    it "is not enabled outside of a count_queries block" do
      ActiveRecord::Base.transaction { true }
      expect(ActiveRecordQueryCounter.transaction_count).to eq nil
      expect(ActiveRecordQueryCounter.transaction_time).to eq nil
      expect(ActiveRecordQueryCounter.transactions).to eq nil
      expect(ActiveRecordQueryCounter.rollback_count).to eq nil
    end

    it "counts the number of transactions inside a block" do
      ActiveRecordQueryCounter.count_queries do
        expect(ActiveRecordQueryCounter.transaction_count).to eq 0
        expect(ActiveRecordQueryCounter.transaction_time).to eq 0

        ActiveRecord::Base.transaction do
          expect(ActiveRecordQueryCounter.transaction_count).to eq 0
          ActiveRecord::Base.transaction do
            expect(ActiveRecordQueryCounter.transaction_count).to eq 0
          end
          expect(ActiveRecordQueryCounter.transaction_count).to eq 0
        end

        expect(ActiveRecordQueryCounter.transaction_count).to eq 1

        ActiveRecord::Base.transaction do
          expect(ActiveRecordQueryCounter.transaction_count).to eq 1
        end

        expect(ActiveRecordQueryCounter.transaction_count).to eq 2
        expect(ActiveRecordQueryCounter.transaction_time).to be > 0
      end
      expect(ActiveRecordQueryCounter.transaction_count).to eq nil
      expect(ActiveRecordQueryCounter.transaction_time).to eq nil
    end

    it "keeps a count and time for each transaction stack trace" do
      ActiveRecordQueryCounter.count_queries do
        TestModel.create!(name: "foo")
        3.times do |i|
          TestModel.create!(name: "record-#{i}")
        end
        TestModel.transaction do
          TestModel.create!(name: "bar")
          TestModel.create!(name: "baz")
        end

        transactions = ActiveRecordQueryCounter.transactions
        expect(transactions.size).to eq 5
        expect(transactions[0].trace).to_not eq transactions[1].trace
        expect(transactions[1].trace).to eq transactions[2].trace
        expect(transactions.sum(&:elapsed_time)).to eq ActiveRecordQueryCounter.transaction_time

        lib_dir = File.expand_path(File.join(__dir__, "..", "lib"))
        transactions.each do |info|
          expect(info.trace.first.start_with?(lib_dir)).to eq false
        end
      end
    end
  end

  describe "counting rollbacks" do
    it "increments the rollback counters" do
      ActiveRecordQueryCounter.count_queries do
        TestModel.transaction do
          TestModel.create!(name: "bar")
          TestModel.create!(name: "baz")
        end
        TestModel.transaction do
          TestModel.create!(name: "baz")
          raise ActiveRecord::Rollback
        end
        expect(ActiveRecordQueryCounter.rollback_count).to eq 1
      end
    end

    it "keeps a count of rollbacks for each rollback" do
      ActiveRecordQueryCounter.count_queries do
        2.times do
          TestModel.transaction do
            TestModel.create!(name: "baz")
            raise ActiveRecord::Rollback
          end
        end
        expect(ActiveRecordQueryCounter.rollback_count).to eq 2
      end
    end
  end

  describe "disable" do
    it "disables counting queries in a block" do
      ActiveRecordQueryCounter.count_queries do
        TestModel.first
        expect(ActiveRecordQueryCounter.query_count).to eq 1

        result = ActiveRecordQueryCounter.disable { TestModel.all.to_a }
        expect(result.map(&:name)).to match_array(["A", "B", "C"])
        expect(ActiveRecordQueryCounter.query_count).to eq 1

        TestModel.last
        expect(ActiveRecordQueryCounter.query_count).to eq 2
      end
    end
  end

  describe "notifications" do
    it "sends a notification when the query count exceeds the threshold" do
      notifications = capture_notifications("query_time") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.query_time = 0
          TestModel.all.to_a
        end
      end
      expect(notifications.size).to eq 1
      expect(notifications.first[:sql]).to eq(TestModel.all.to_sql)
      expect(notifications.first[:binds]).to be_a(Array)
      expect(notifications.first[:row_count]).to eq 3
      expect(notifications.first[:trace]).to be_a(Array)
      expect(notifications.first[:duration]).to be >= 0
    end

    it "does not send a notification when the query count does not exceed the threshold" do
      notifications = capture_notifications("query_time") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.query_time = 5
          TestModel.all.to_a
        end
      end
      expect(notifications).to be_empty
    end

    it "sends a notification when the row count exceeds the threshold" do
      notifications = capture_notifications("row_count") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.row_count = 2
          TestModel.all.to_a
        end
      end
      expect(notifications.size).to eq 1
      expect(notifications.first[:sql]).to eq(TestModel.all.to_sql)
      expect(notifications.first[:binds]).to be_a(Array)
      expect(notifications.first[:row_count]).to eq 3
      expect(notifications.first[:trace]).to be_a(Array)
      expect(notifications.first[:duration]).to be >= 0
    end

    it "does not send a notification when the row count does not exceed the threshold" do
      notifications = capture_notifications("row_count") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.row_count = 5
          TestModel.all.to_a
        end
      end
      expect(notifications).to be_empty
    end

    it "sends a notification when the transaction time exceeds the threshold" do
      notifications = capture_notifications("transaction_time") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.transaction_time = 0
          TestModel.create!(name: "new")
        end
      end
      expect(notifications.size).to eq 1
      expect(notifications.first[:trace]).to be_a(Array)
      expect(notifications.first[:duration]).to be > 0
    end

    it "does not send a notification when the transaction time does not exceed the threshold" do
      notifications = capture_notifications("transaction_time") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.transaction_time = 5
          TestModel.create!(name: "new")
        end
      end
      expect(notifications).to be_empty
    end

    it "sends a notification when the transaction count exceeds the threshold" do
      notifications = capture_notifications("transaction_count") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.transaction_count = 1
          TestModel.create!(name: "new 1")
          TestModel.create!(name: "new 2")
        end
      end
      expect(notifications.size).to eq 1
      expect(notifications.first[:transactions].size).to eq 2
      expect(notifications.first[:duration]).to be > notifications.first[:transactions].first.elapsed_time
    end

    it "does not send a notification when the transaction count does not exceed the threshold" do
      notifications = capture_notifications("transaction_count") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.transaction_count = 5
          ActiveRecord::Base.transaction { true }
        end
      end
      expect(notifications).to be_empty
    end
  end

  describe "thresholds" do
    it "can set global and counter thresholds" do
      ActiveRecordQueryCounter.default_thresholds.query_time = 1
      expect(ActiveRecordQueryCounter.default_thresholds.query_time).to eq 1

      ActiveRecordQueryCounter.default_thresholds.row_count = 10
      expect(ActiveRecordQueryCounter.default_thresholds.row_count).to eq 10

      ActiveRecordQueryCounter.default_thresholds.transaction_time = 5
      expect(ActiveRecordQueryCounter.default_thresholds.transaction_time).to eq 5

      ActiveRecordQueryCounter.default_thresholds.transaction_count = 2
      expect(ActiveRecordQueryCounter.default_thresholds.transaction_count).to eq 2

      counter = ActiveRecordQueryCounter::Counter.new
      expect(counter.thresholds.query_time).to eq 1
      expect(counter.thresholds.row_count).to eq 10
      expect(counter.thresholds.transaction_time).to eq 5
      expect(counter.thresholds.transaction_count).to eq 2

      counter.thresholds.query_time = 2
      expect(counter.thresholds.query_time).to eq 2
      expect(ActiveRecordQueryCounter.default_thresholds.query_time).to eq 1
    ensure
      ActiveRecordQueryCounter.default_thresholds.query_time = nil
      ActiveRecordQueryCounter.default_thresholds.row_count = nil
      ActiveRecordQueryCounter.default_thresholds.transaction_time = nil
      ActiveRecordQueryCounter.default_thresholds.transaction_count = nil
    end

    it "can set thresholds just for the current counter" do
      ActiveRecordQueryCounter.count_queries do
        counter = ActiveRecordQueryCounter.send(:current_counter)
        ActiveRecordQueryCounter.thresholds.query_time = 1
        expect(counter.thresholds.query_time).to eq 1
        expect(ActiveRecordQueryCounter.default_thresholds.query_time).to eq nil
      end
    end

    it "does nothing when there is no current counter" do
      ActiveRecordQueryCounter.thresholds.query_time = 1
      expect(ActiveRecordQueryCounter.default_thresholds.query_time).to eq nil
    end
  end

  describe "database query time" do
    # elapsed_time, gc_time, and cpu_time are passed directly so the timing does not depend on
    # the host's clock behavior. add_query is the method the connection adapter calls with the
    # measured timings.
    def add_query(elapsed:, gc:, cpu:, row_count: 1, name: "TestModel Load")
      ActiveRecordQueryCounter.add_query("SELECT 1", name, [], row_count, 100.0, 100.0 + elapsed, gc, cpu)
    end

    describe "database_query_time" do
      it "subtracts the gc time and cpu time from the elapsed time" do
        expect(ActiveRecordQueryCounter.send(:database_query_time, 10.0, 2.0, 3.0)).to eq 5.0
      end

      it "returns the full elapsed time when there is no gc or cpu time" do
        expect(ActiveRecordQueryCounter.send(:database_query_time, 4.0, 0.0, 0.0)).to eq 4.0
      end

      it "subtracts only the larger of gc and cpu time when subtracting both would go negative" do
        # 10 - 8 - 7 = -5, so fall back to 10 - max(8, 7) = 2 rather than double counting.
        expect(ActiveRecordQueryCounter.send(:database_query_time, 10.0, 8.0, 7.0)).to eq 2.0
      end

      it "never returns a negative value" do
        expect(ActiveRecordQueryCounter.send(:database_query_time, 1.0, 5.0, 5.0)).to eq 0.0
      end

      it "returns zero when no time elapsed" do
        expect(ActiveRecordQueryCounter.send(:database_query_time, 0.0, 1.0, 1.0)).to eq 0.0
      end
    end

    it "accumulates the database query time rather than the wall clock time" do
      ActiveRecordQueryCounter.count_queries do
        add_query(elapsed: 10.0, gc: 2.0, cpu: 3.0)
        expect(ActiveRecordQueryCounter.query_time).to eq 5.0
      end
    end

    it "uses the database query time as the notification duration" do
      notifications = capture_notifications("query_time") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecordQueryCounter.thresholds.query_time = 0
          add_query(elapsed: 10.0, gc: 2.0, cpu: 3.0)
        end
      end
      expect(notifications.size).to eq 1
      # The duration is the database query time (5s = elapsed 10 - gc 2 - cpu 3) in milliseconds,
      # not the raw wall clock time.
      expect(notifications.first[:duration]).to be_within(0.001).of(5000.0)
    end

    it "compares the database query time, not the wall clock time, against the threshold" do
      notifications = capture_notifications("query_time") do
        ActiveRecordQueryCounter.count_queries do
          # Wall clock time (10) exceeds the threshold, but the database time (5) does not.
          ActiveRecordQueryCounter.thresholds.query_time = 6
          add_query(elapsed: 10.0, gc: 2.0, cpu: 3.0)
        end
      end
      expect(notifications).to be_empty
    end
  end
end
