class ParserController < ApplicationController
  def parse
    begin
      result = OscParser.new.parse params[:msg]
    rescue => e
      result = nil
      error = e.message
    else
      error = nil
    end

    render json: {
      :respond => result,
      :error => error
    }
  end
end
