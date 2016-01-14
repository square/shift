class MetaRequestMailer < ActionMailer::Base
  @@mailer_config = Rails.application.config.x.mailer
  default from: @@mailer_config[:default_from]

  def new_meta_request(meta_request)
    @meta_request = MetaRequest.find(meta_request.id)
    recipients = [@@mailer_config[:default_to] + @@mailer_config[:default_to_domain]]
    mail(to: recipients, subject: "New OSC meta request: METAREQUEST-#{@meta_request.id} [#{ENV['RAILS_ENV']}]")
  end
end
