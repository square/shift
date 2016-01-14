require 'coverage_helper'
require 'factory_girl_rails'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.use_transactional_fixtures = true
  config.include FactoryGirl::Syntax::Methods

  config.before(:each) do
    DatabaseCleaner.start
    Rails.application.load_seed
  end
end
