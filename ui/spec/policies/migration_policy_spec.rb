require 'policies_helper'

RSpec.describe MigrationPolicy do
  subject { described_class }

  let(:normal_user) { {
      :username => "developer",
      :capabilities => [],
    } }
  let(:admin_user) { {
      :username => "admin",
      :capabilities => ["admin"],
    } }

  before(:each) do
    @cluster = FactoryGirl.create(:cluster)
    @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name)
  end

  permissions :approve? do
    it "denies access if the user isn't an admin and isn't a cluster admin" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: "other_user")
      expect(subject).not_to permit(normal_user, @migration)
    end

    it "denies access if the user isn't an admin, is a cluster owner,
        and admin review is required" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: normal_user[:username])
      @cluster.update_attribute(:admin_review_required, true)
      expect(subject).not_to permit(normal_user, @migration)
    end

    it "denies access if the user isn't an admin, is a cluster owner, admin review is
        not required, and the user is the requestor" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: normal_user[:username])
      @cluster.update_attribute(:admin_review_required, false)
      @migration.update_attribute(:requestor, normal_user[:username])
      expect(subject).not_to permit(normal_user, @migration)
    end

    it "grants access if the user is an admin" do
      expect(subject).to permit(admin_user, @migration)
    end

    it "grants access if the user is a cluster admin, admin review is not required, and
        the user isn't the original requestor" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: normal_user[:username])
      @cluster.update_attribute(:admin_review_required, false)
      @migration.update_attribute(:requestor, "someone_else")
      expect(subject).to permit(normal_user, @migration)
    end
  end

  permissions :approve_dangerous? do
    it "denies access if the user isn't an admin" do
      expect(subject).not_to permit(normal_user, @migration)
    end

    it "grants access if the user is an admin" do
      expect(subject).to permit(admin_user, @migration)
    end
  end

  permissions :run_action? do
    it "denies access if the user isn't an admin or cluster admin" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: "other_user")
      expect(subject).not_to permit(normal_user, @migration)
    end

    it "grants access if the user is an admin" do
      expect(subject).to permit(admin_user, @migration)
    end

    it "grants access if the user is a cluster admin" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: normal_user[:username])
      expect(subject).to permit(admin_user, @migration)
    end
  end

  permissions :any_action? do
    it "denies access if the user isn't an admin" do
      expect(subject).not_to permit(normal_user, @migration)
    end

    it "grants access if the user is an admin" do
      expect(subject).to permit(admin_user, @migration)
    end
  end

  permissions :destroy? do
    it "denies access if the user isn't an admin or cluster admin or the requestor" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: "other_user")
      @migration.update_attribute(:requestor, "someone_else")
      expect(subject).not_to permit(normal_user, @migration)
    end

    it "grants access if the user is an admin" do
      expect(subject).to permit(admin_user, @migration)
    end

    it "grants access if the user is a cluster admin" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: normal_user[:username])
      expect(subject).to permit(admin_user, @migration)
    end

    it "grants access if the user is the requestor" do
      FactoryGirl.create(:owner, cluster_name: @migration.cluster_name, username: "other_user")
      @migration.update_attribute(:requestor, normal_user[:username])
      expect(subject).to permit(normal_user, @migration)
    end
  end
end
