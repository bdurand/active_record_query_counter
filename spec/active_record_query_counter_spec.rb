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
          rollbacks: 0
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
        expect(ActiveRecordQueryCounter.query_time).to be > 0

        ActiveRecord::Base.transaction { true }

        expect(ActiveRecordQueryCounter.info).to eq({
          query_count: 2,
          row_count: 4,
          query_time: ActiveRecordQueryCounter.query_time,
          cached_query_count: 0,
          cache_hit_rate: 0.0,
          transaction_count: 1,
          transaction_time: ActiveRecordQueryCounter.transaction_time,
          rollbacks: 0
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
            rollbacks: 0
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

    it "keeps a count of rollbacks for each transaction trace" do
      ActiveRecordQueryCounter.count_queries do
        TestModel.transaction do
          TestModel.create!(name: "baz")
          raise ActiveRecord::Rollback
        end
        expect(ActiveRecordQueryCounter.rollbacks).to eq 1
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
      expect(notifications.first[:duration]).to be > 0
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
      expect(notifications.first[:duration]).to be > 0
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
end
