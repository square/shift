begin
  require 'rspec/core/rake_task'

  namespace :spec do
    %w(acceptance unit integration policies lint).each do |type|
      RSpec::Core::RakeTask.new(type) do |t|
        t.pattern = "./spec/#{type}/**/*_spec.rb"
      end
    end
  end

  desc "Run all specs"
  task :spec => [
    :'spec:unit',
    :'spec:integration',
    :'spec:policies',
    :'spec:acceptance',
    :'spec:lint'
  ]
  task :default => :spec
rescue LoadError
  warn "rspec not available"
end

begin
  require 'cane/rake_task'

  desc "Run cane to check quality metrics"
  Cane::RakeTask.new(:quality) do |cane|
    cane.abc_max = 10
    cane.add_threshold 'coverage/covered_percent', :>=, 95
    cane.no_style = true
  end

  task :default => :quality
rescue LoadError
  warn "cane not available"
end
