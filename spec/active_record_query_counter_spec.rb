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
        expect(transactions.size).to eq 3
        expect(transactions.values.collect(&:count)).to eq [1, 3, 1]
        expect(transactions.values.sum(&:elapsed_time)).to eq ActiveRecordQueryCounter.transaction_time

        lib_dir = File.expand_path("../../lib", __FILE__)
        transactions.keys.each do |trace|
          expect(trace.first.start_with?(lib_dir)).to eq false
        end
      end
    end
  end

  describe ActiveRecordQueryCounter::RackMiddleware do
    it "enables query counting" do
      app = lambda do |env|
        TestModel.all.to_a
        [200, env, ["queries: #{ActiveRecordQueryCounter.query_count}, rows: #{ActiveRecordQueryCounter.row_count}"]]
      end

      middleware = ActiveRecordQueryCounter::RackMiddleware.new(app)
      result = middleware.call("foo" => "bar")
      expect(result).to eq [200, {"foo" => "bar"}, ["queries: 1, rows: 3"]]
    end
  end

  describe ActiveRecordQueryCounter::SidekiqMiddleware do
    it "enables query counting" do
      middleware = ActiveRecordQueryCounter::SidekiqMiddleware.new
      query_count = nil
      row_count = nil
      middleware.call(:worker, {}, "queue") do
        TestModel.all.to_a
        query_count = ActiveRecordQueryCounter.query_count
        row_count = ActiveRecordQueryCounter.row_count
      end
      expect(query_count).to eq 1
      expect(row_count).to eq 3
    end
  end
end
