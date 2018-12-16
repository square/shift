# Parent class for all controllers.
class ApplicationController < ActionController::Base
  include Pundit

  protect_from_forgery
  before_filter :current_user

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def current_user
    dn = request.headers["x-ssl-client-s-dn"] || ""
    who_pair = dn.split(",").find{|i| i.start_with?("CN=")}
    who = who_pair ? who_pair.split("=")[1].upcase: "UNKNOWN"

    is_admin = Rails.configuration.x.admins.include?(who)
    @current_user = {
      :username => who,
      :capabilities => is_admin ? ["admin"]: [],
    }
  end

  def current_user_name
    @current_user[:username]
  end
  helper_method :current_user_name

  def record_not_found
    render :text => "404 Not Found", :status => 404
  end

  def user_not_authorized
    return render text: "You are not authorized to perform this action.", status: :unauthorized
  end

  def user_is_admin?
    (current_user[:capabilities].include? 'admin')
  end
  helper_method :user_is_admin?

  def require_admin
    render :template => "errors/error401", :status => 401 unless user_is_admin?
  end

  # extend rails' word_wrap to break up long words. this helps us in our views when someone submits
  # a ddl statement with a super long word in it
  def breaking_word_wrap(text, *args)
    options = args.extract_options!
    unless args.blank?
      options[:line_width] = args[0] || 80
    end
    options.reverse_merge!(:line_width => 80)
    text = text.split(" ").collect do |word|
      word.length > options[:line_width] ? word.gsub(/(.{1,#{options[:line_width]}})/, "\\1 ") : word
    end * " "
    text.split("\n").collect do |line|
      line.length > options[:line_width] ? line.gsub(/(.{1,#{options[:line_width]}})(\s+|$)/, "\\1\n").strip : line
    end * "\n"
  end
  helper_method :breaking_word_wrap
end
