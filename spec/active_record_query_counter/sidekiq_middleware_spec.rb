# frozen_string_literal: true

require_relative "../spec_helper"

describe ActiveRecordQueryCounter::SidekiqMiddleware do
  before :each do
    TestModel.create!(name: "A")
    TestModel.create!(name: "B")
    TestModel.create!(name: "C")
  end

  after :each do
    TestModel.destroy_all
  end

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

  it "can set thresholds" do
    middleware = ActiveRecordQueryCounter::SidekiqMiddleware.new
    query_time = nil
    row_count = nil
    transaction_time = nil
    transaction_count = nil
    threshold_options = {
      "query_time" => 1.5,
      "row_count" => 100,
      "transaction_time" => 2.5,
      "transaction_count" => 1
    }
    middleware.call(:worker, {"active_record_query_counter" => {"thresholds" => threshold_options}}, "queue") do
      t = ActiveRecordQueryCounter.thresholds
      query_time = t.query_time
      row_count = t.row_count
      transaction_time = t.transaction_time
      transaction_count = t.transaction_count
    end
    expect(query_time).to eq 1.5
    expect(row_count).to eq 100
    expect(transaction_time).to eq 2.5
    expect(transaction_count).to eq 1
  end

  it "can disable thresholds" do
    ActiveRecordQueryCounter.default_thresholds.set(
      query_time: 1.5,
      row_count: 100,
      transaction_time: 2.5,
      transaction_count: 1
    )

    middleware = ActiveRecordQueryCounter::SidekiqMiddleware.new
    query_time = nil
    row_count = nil
    transaction_time = nil
    transaction_count = nil
    middleware.call(:worker, {"active_record_query_counter" => {"thresholds" => false}}, "queue") do
      t = ActiveRecordQueryCounter.thresholds
      query_time = t.query_time
      row_count = t.row_count
      transaction_time = t.transaction_time
      transaction_count = t.transaction_count
    end
    expect(query_time).to eq nil
    expect(row_count).to eq nil
    expect(transaction_time).to eq nil
    expect(transaction_count).to eq nil
  ensure
    ActiveRecordQueryCounter.default_thresholds.clear
  end
end
