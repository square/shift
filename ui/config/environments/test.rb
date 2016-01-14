Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # The test environment is used exclusively to run your application's
  # test suite. You never need to work with it otherwise. Remember that
  # your test database is "scratch space" for the test suite and is wiped
  # and recreated between test runs. Don't rely on the data there!
  config.cache_classes = true

  # Do not eager load code on boot. This avoids loading your whole application
  # just for the purpose of running a single test. If you are using a tool that
  # preloads Rails for running tests, you may have to set it to true.
  config.eager_load = false

  # Configure static file server for tests with Cache-Control for performance.
  config.serve_static_files   = true
  config.static_cache_control = 'public, max-age=3600'

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = false

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Randomize the order test cases are executed.
  config.active_support.test_order = :random

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations
  # config.action_view.raise_on_missing_translations = true

  config.action_mailer.default_url_options = { :host => 'test.host.com' }
  config.action_mailer.perform_deliveries = false


  ########################
  # SHIFT-SPECIFIC CONFIGS
  ########################

  ## mysql_helper
  # read-only credentials for shift to connect to and inspect all hosts
  config.x.mysql_helper.db_config = {
    :username => "root",
  }
  # databases to exclude running oscs on
  config.x.mysql_helper.db_blacklist =
    ["information_schema", "mysql", "performance_schema", "_pending_drops",
     "common_schema"]

  ## mailer stuff
  config.x.mailer.default_from = "shift@your_domain"
  config.x.mailer.default_to = "your_local_name"
  config.x.mailer.default_to_domain = "@your_domain"

  ## ptosc
  # root path for pt-osc output logs. specified within shift-runner
  config.x.ptosc.log_dir = "/tmp/shift/"
end
