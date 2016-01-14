require File.expand_path('../boot', __FILE__)

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Shift
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
    config.i18n.enforce_available_locales

    # Default to SQL schema format for performant and exact expression of
    # datbase schemas.
    config.active_record.schema_format = :ruby

    # Override default jruby-rack log (stdout)
    config.logger = ActiveSupport::Logger.new("log/#{Rails.env}.log")

    # When sending multiple concurrent requests at a Rails application running
    # under JRuby on Tomcat, the first few requests have env_config not fully
    # initialized. This happens because one thread may kick off
    # Engine.env_config and set the instance variable but not have a chance to
    # fully process Application.env_config yet. This causes a different request
    # get only Engine.env_config initialized hash, which is missing important
    # settings like secret token.
    # https://github.com/rails/rails/issues/5824
    config.after_initialize do
      env_config
    end

    require Rails.root.join("app/services/custom_public_exceptions")
    config.exceptions_app = CustomPublicExceptions.new(Rails.public_path)
  end
end
