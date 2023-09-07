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
end
