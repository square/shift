class ErrorsController < ApplicationController
  def error404
    render status: :not_found
  end
end
