require 'fileutils'

# Provides endpoints to read log files for a migration. Assumes
# that shift-runner runs and creates pt-osc log files on the
# same host as the shift ui
class LogController < ApplicationController
  skip_before_filter :current_user
  def ptosc_log_file
    ptosc_id = params[:id]
    log_file = Rails.application.config.x.ptosc.log_dir + "/id-#{ptosc_id}/ptosc-output.log"
    if File.file?(log_file)
      render text: File.read(log_file), layout: false, content_type: 'text/plain'
    else
      render text: "Log file not found.", layout: false, content_type: 'text/plain'
    end
  end
end
