$LOAD_PATH.unshift("./app/services")
$LOAD_PATH.unshift("./app/models")

require 'coverage_helper'
require 'factory_girl_rails'

SimpleCov.command_name 'spec:unit' if RUBY_PLATFORM != 'java'

RSpec.configure do |config|
  config.mock_with :rspec
  config.use_transactional_fixtures = true
  config.include FactoryGirl::Syntax::Methods

  config.before(:each) do
    DatabaseCleaner.start
    Rails.application.load_seed
  end
end
