class MigrationPolicy
  attr_reader :user, :migration

  def initialize(user, migration)
    @user = user
    @migration = migration
  end

  # applies to approve/unapprove
  def approve?
    approver?
  end

  def approve_dangerous?
    admin?
  end

  # applies to start, pause, rename, resume, dequeue, and cancel
  def run_action?
    admin? || cluster_owner?
  end

  # applues to any action
  def any_action?
    admin?
  end

  def destroy?
    admin? || cluster_owner? ||
      migration_requestor?
  end

  private

  def admin?
    (@user[:capabilities].include? 'admin') || Rails.env.development?
  end

  def approver?
    admin? || (cluster_owner? && !admin_review_required? &&
               !migration_requestor?)
  end

  def cluster_owner?
    @migration.cluster.owners.collect(&:username).include?(current_user_name)
  end

  def admin_review_required?
    @migration.cluster.admin_review_required?
  end

  def migration_requestor?
    current_user_name == @migration.requestor
  end

  def current_user_name
    @user[:username]
  end
end
