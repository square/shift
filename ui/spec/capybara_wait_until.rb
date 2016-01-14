module Capybara
  class Session
    ##
    #
    # Retry executing the block until a truthy result is returned or the timeout time is exceeded
    #
    # @param [Integer] timeout   The amount of seconds to retry executing the given block
    #
    # this method was removed in Capybara v2 so adding it back if not already defined
    #
    unless defined?(wait_until)
      def wait_until(timeout = Capybara.default_max_wait_time)
        Capybara.send(:timeout, timeout, driver) { yield }
      end
    end
  end
end
