require 'fileutils'

# Provides internal endpoints to support health checks.
class HealthController < ApplicationController
  skip_before_filter :current_user
  class WarningException < StandardError; end

  DISABLE_FILE_PATH = Rails.root.join("tmp", "maintenance")

  def status
    rescue_exceptions do
      verify_enabled
      verify_database
    end
  end

  private
  def rescue_exceptions
    yield
    render json: { status: :ok }
  rescue WarningException => e
    render json: { status: :warning, message: e.message }, status: 200
  rescue Exception => e
    render json: { status: :critical, message: e.message }, status: 500
  end

  def verify_enabled
    raise "Server is Disabled" if File.exists?(DISABLE_FILE_PATH)
  end

  def verify_database
    ActiveRecord::Base.connection.select_all "SELECT 1"
  end
end
