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
      expect(ActiveRecordQueryCounter.info).to eq nil
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
          transaction_count: 1,
          transaction_time: ActiveRecordQueryCounter.transaction_time
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

          result = TestModel.find_by(name: "B")
          expect(result.name).to eq "B"
          expect(ActiveRecordQueryCounter.query_count).to eq 1
          expect(ActiveRecordQueryCounter.row_count).to eq 1
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
        expect(ActiveRecordQueryCounter.transaction_time).to be < ActiveRecordQueryCounter.single_transaction_time

        lib_dir = File.expand_path(File.join(__dir__, "..", "lib"))
        transactions.each do |info|
          expect(info.trace.first.start_with?(lib_dir)).to eq false
        end
      end
    end
  end

  describe "notifications" do
    it "sends a notification when the query count exceeds the threshold" do
      ActiveRecordQueryCounter.query_time_threshold = 0
      notifications = capture_notifications("active_record_query_counter.query_time") do
        ActiveRecordQueryCounter.count_queries do
          TestModel.all.to_a
        end
      end
      expect(notifications.size).to eq 1
      expect(notifications.first[:sql]).to eq(TestModel.all.to_sql)
      expect(notifications.first[:trace]).to_not be_nil
    ensure
      ActiveRecordQueryCounter.query_time_threshold = nil
    end

    it "does not send a notification when the query count does not exceed the threshold" do
      ActiveRecordQueryCounter.query_time_threshold = 5
      notifications = capture_notifications("active_record_query_counter.query_time") do
        ActiveRecordQueryCounter.count_queries do
          TestModel.all.to_a
        end
      end
      expect(notifications).to be_empty
    ensure
      ActiveRecordQueryCounter.query_time_threshold = nil
    end

    it "sends a notification when the row count exceeds the threshold" do
      ActiveRecordQueryCounter.row_count_threshold = 2
      notifications = capture_notifications("active_record_query_counter.row_count") do
        ActiveRecordQueryCounter.count_queries do
          TestModel.all.to_a
        end
      end
      expect(notifications.size).to eq 1
      expect(notifications.first[:sql]).to eq(TestModel.all.to_sql)
      expect(notifications.first[:row_count]).to eq 3
      expect(notifications.first[:trace]).to_not be_nil
    ensure
      ActiveRecordQueryCounter.row_count_threshold = nil
    end

    it "does not send a notification when the row count does not exceed the threshold" do
      ActiveRecordQueryCounter.row_count_threshold = 5
      notifications = capture_notifications("active_record_query_counter.row_count") do
        ActiveRecordQueryCounter.count_queries do
          TestModel.all.to_a
        end
      end
      expect(notifications).to be_empty
    ensure
      ActiveRecordQueryCounter.row_count_threshold = nil
    end

    it "sends a notification when the transaction time exceeds the threshold" do
      ActiveRecordQueryCounter.transaction_time_threshold = 0
      notifications = capture_notifications("active_record_query_counter.transaction_time") do
        ActiveRecordQueryCounter.count_queries do
          TestModel.create!(name: "new")
        end
      end
      expect(notifications.size).to eq 1
      expect(notifications.first[:trace]).to_not be_nil
    ensure
      ActiveRecordQueryCounter.transaction_time_threshold = nil
    end

    it "does not send a notification when the transaction time does not exceed the threshold" do
      ActiveRecordQueryCounter.transaction_time_threshold = 5
      notifications = capture_notifications("active_record_query_counter.transaction_time") do
        ActiveRecordQueryCounter.count_queries do
          TestModel.create!(name: "new")
        end
      end
      expect(notifications).to be_empty
    ensure
      ActiveRecordQueryCounter.transaction_time_threshold = nil
    end

    it "sends a notification when the transaction count exceeds the threshold" do
      ActiveRecordQueryCounter.transaction_count_threshold = 1
      notifications = capture_notifications("active_record_query_counter.transaction_count") do
        ActiveRecordQueryCounter.count_queries do
          TestModel.create!(name: "new 1")
          TestModel.create!(name: "new 2")
        end
      end
      expect(notifications.size).to eq 1
      expect(notifications.first[:transaction_count]).to eq 2
      expect(notifications.first[:trace]).to_not be_nil
    ensure
      ActiveRecordQueryCounter.transaction_count_threshold = nil
    end

    it "does not send a notification when the transaction count does not exceed the threshold" do
      ActiveRecordQueryCounter.transaction_count_threshold = 5
      notifications = capture_notifications("active_record_query_counter.transaction_count") do
        ActiveRecordQueryCounter.count_queries do
          ActiveRecord::Base.transaction { true }
        end
      end
      expect(notifications).to be_empty
    ensure
      ActiveRecordQueryCounter.transaction_count_threshold = nil
    end
  end
end
