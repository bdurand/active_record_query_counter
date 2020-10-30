Gem::Specification.new do |spec|
  spec.name = "active_record_query_counter"
  spec.version = File.read(File.expand_path("../VERSION", __FILE__)).strip
  spec.authors = ["Brian Durand"]
  spec.email = ["bbdurand@gmail.com"]

  spec.summary = "Count total number of ActiveRecord queries and row counts inside a block"
  spec.homepage = "https://github.com/bdurand/active_record_query_counter"
  spec.license = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  ignore_files = %w[
    .gitignore
    .travis.yml
    Appraisals
    Gemfile
    Gemfile.lock
    Rakefile
    gemfiles/
    spec/
  ]
  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| ignore_files.any? { |path| f.start_with?(path) } }
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 4.2"

  spec.add_development_dependency "bundler", "~>2.0"
  spec.add_development_dependency "rspec", ["~> 3.0"]
  spec.add_development_dependency "sqlite3"

end
