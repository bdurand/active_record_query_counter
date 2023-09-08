# frozen_string_literal: true

require_relative "../spec_helper"

describe ActiveRecordQueryCounter::RackMiddleware do
  before :each do
    TestModel.create!(name: "A")
    TestModel.create!(name: "B")
    TestModel.create!(name: "C")
  end

  after :each do
    TestModel.destroy_all
  end

  it "enables query counting" do
    app = lambda do |env|
      TestModel.all.to_a
      [200, env, ["queries: #{ActiveRecordQueryCounter.query_count}, rows: #{ActiveRecordQueryCounter.row_count}"]]
    end

    middleware = ActiveRecordQueryCounter::RackMiddleware.new(app)
    result = middleware.call("foo" => "bar")
    expect(result).to eq [200, {"foo" => "bar"}, ["queries: 1, rows: 3"]]
  end

  it "can set thresholds" do
    app = lambda do |env|
      t = ActiveRecordQueryCounter.thresholds
      headers = {
        "query_time" => t.query_time,
        "row_count" => t.row_count,
        "transaction_time" => t.transaction_time,
        "transaction_count" => t.transaction_count
      }
      [200, headers, ["OK"]]
    end

    middleware = ActiveRecordQueryCounter::RackMiddleware.new(app, thresholds: {query_time: 1.5, row_count: 100, transaction_time: 2.5, transaction_count: 1})
    result = middleware.call("foo" => "bar")
    expect(result[1]).to eq({
      "query_time" => 1.5,
      "row_count" => 100,
      "transaction_time" => 2.5,
      "transaction_count" => 1
    })
  end
end
