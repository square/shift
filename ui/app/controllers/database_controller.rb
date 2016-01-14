class DatabaseController < ApplicationController
  def fetch
    render json: {
      :databases => MysqlHelper.safe_databases(params[:cluster])
    }
  end
end