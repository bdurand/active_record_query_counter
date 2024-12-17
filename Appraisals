RAILS_MINOR_RELEASES = ["8.0", "7.1", "7.0", "6.1", "6.0", "5.2", "5.1"].freeze

appraise "activerecord_8.0" do
  gem "activerecord", "~> 8.0.0"
  gem "sqlite3", "~> 2.2"
end

appraise "activerecord_7.2" do
  gem "activerecord", "~> 7.2.0"
  gem "sqlite3", "~> 1.4.0"
end

appraise "activerecord_7.1" do
  gem "activerecord", "~> 7.1.0"
  gem "sqlite3", "~> 1.4.0"
end

appraise "activerecord_7.0" do
  gem "activerecord", "~> 7.0.0"
  gem "sqlite3", "~> 1.4.0"
end

appraise "activerecord_6.1" do
  gem "activerecord", "~> 6.1.0"
  gem "sqlite3", "~> 1.4.0"
end

appraise "activerecord_6.0" do
  gem "activerecord", "~> 6.0.0"
  gem "sqlite3", "~> 1.4.0"
end

appraise "activerecord_5.2" do
  gem "activerecord", "~> 5.2.0"
  gem "sqlite3", "~> 1.3.0"
end

appraise "activerecord_5.1" do
  gem "activerecord", "~> 5.2.0"
  gem "sqlite3", "~> 1.3.0"
end

appraise "without-sidekiq" do
  remove_gem "sidekiq"
end

appraise "sidekiq-7" do
  gem "sidekiq", "~> 7.0"
end

appraise "sidekiq-6" do
  gem "sidekiq", "~> 6.0"
  gem "activerecord", "~> 7.0"
  gem "sqlite3", "~> 1.4.0"
end

appraise "sidekiq-5" do
  gem "sidekiq", "~> 5.0"
  gem "activerecord", "~> 5.2"
  gem "sqlite3", "~> 1.3.0"
end
