$LOAD_PATH.unshift("./app/controllers")

require 'coverage_helper'
require 'rails_helper'
require 'fdoc/spec_watcher'
require 'factory_girl_rails'

Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

SimpleCov.command_name 'spec:integration' if RUBY_PLATFORM != 'java'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.use_transactional_fixtures = true
  config.include FactoryGirl::Syntax::Methods

  config.include Requests::JsonHelper, :type => :controller

  config.before(:each) do
    DatabaseCleaner.start
    Rails.application.load_seed
  end
end
