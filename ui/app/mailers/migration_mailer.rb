class MigrationMailer < ActionMailer::Base
  @@mailer_config = Rails.application.config.x.mailer
  default from: @@mailer_config[:default_from]

  def new_migration(migration)
    @migration = Migration.find(migration.dao.id)
    recipients = [@@mailer_config[:default_to] + @@mailer_config[:default_to_domain]]
    mail(to: recipients, subject: "New OSC request: OSC-#{@migration.id} [#{ENV['RAILS_ENV']}]")
  end

  def migration_status_change(migration)
    @migration = migration
    @status = Statuses.find_by_status!(@migration.status)
    if Rails.env.production?
      # email the requestor and approver
      recipients = [@migration.requestor + @@mailer_config[:default_to_domain]]
      recipients << @migration.approved_by + @@mailer_config[:default_to_domain] if @migration.approved_by
    else
      recipients = [@@mailer_config[:default_to] + @@mailer_config[:default_to_domain]]
    end
    mail(to: recipients, subject: "Shift Status Update: osc-#{@migration.id}")
  end

  def migration_comment(comment)
    @comment = comment
    @migration = Migration.find(@comment.migration_id)
    profile_client = Profile.new
    @person = {:photo => profile_client.primary_photo(@comment.author)}

    if Rails.env.production?
      # get all of the people involved in the migration
      recipients = Comment.where(:migration_id => @comment.migration_id).pluck(:author)
      recipients << @migration.requestor
      recipients << @migration.approved_by if @migration.approved_by
      recipients << @@mailer_config[:default_to] + @@mailer_config[:default_to_domain]
      # remove the person who just commented
      recipients.delete(comment.author)

      recipients.collect! {|r| r + @@mailer_config[:default_to_domain] }.uniq
    else
      recipients = [@@mailer_config[:default_to] + @@mailer_config[:default_to_domain]]
    end
    mail(to: recipients, subject: "Shift Status Update: osc-#{@comment.migration_id}")
  end
end
