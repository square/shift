ENV['ACCEPTANCE'] = 'true'
require 'coverage_helper'
require 'rails_helper'
require 'factory_girl_rails'

require 'capybara/rails'
require 'capybara/rspec'
require 'capybara/poltergeist'
require 'database_cleaner'

SimpleCov.command_name 'spec:acceptance' if RUBY_PLATFORM != 'java'

Capybara.server_port = 3001

Capybara.default_max_wait_time = 20
Capybara.javascript_driver = :poltergeist

RSpec.configure do |config|
  config.include Capybara::DSL
  config.include FactoryGirl::Syntax::Methods

  config.before(:suite) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start
    Rails.application.load_seed
  end

  config.before(:all) do
    init_capybara
  end

  config.after(:each) { DatabaseCleaner.clean }

  def init_capybara
    visit '/'
  end
end
