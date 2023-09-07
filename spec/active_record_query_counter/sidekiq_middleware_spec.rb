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
end
