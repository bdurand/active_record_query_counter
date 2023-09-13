RAILS_MINOR_RELEASES = ["7.0", "6.1", "6.0", "5.2", "5.1"].freeze

RAILS_MINOR_RELEASES.each do |version|
  appraise "activerecord-#{version}" do
    gem "activerecord", "~> #{version}.0"
    if version.to_f < 5.2
      gem "sqlite3", "~> 1.3.0"
    else
      gem "sqlite3", "~> 1.4.0"
    end
  end
end

appraise "without-sidekiq" do
  remove_gem "sidekiq"
end

appraise "sidekiq-6" do
  gem "sidekiq", "~> 6.0"
  gem "activerecord", "~> 6.0"
end
