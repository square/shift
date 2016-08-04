require 'integration_helper'
require 'shared_setup'

RSpec.describe Migration do
  include_context "shared setup"

  describe 'migrations_by_state' do
    it 'returns a list of migrations by group' do
      migration = FactoryGirl.create(:human_migration)
      human_migrations = Migration.migrations_by_state(:human)
      expect(human_migrations[0]).to eq(migration)
    end
  end

  describe 'counts_by_state' do
    it 'returns a list of migration counts by group' do
      FactoryGirl.create(:pending_migration)
      migration = FactoryGirl.create(:pending_migration)
      migration.cluster_name = "something_new"
      migration.save

      counts = Migration.counts_by_state(["pending"])
      expect(counts["pending"]).to eq(2)

      counts = Migration.counts_by_state(["pending"], additional_filters: {:cluster_name => "something_new"})
      expect(counts["pending"]).to eq(1)
    end
  end

  describe 'pending?' do
    context 'is pending' do
      it 'returns that the migration is pending' do
        migration = FactoryGirl.create(:pending_migration)
        expect(migration.pending?).to eq(true)
      end
    end

    context 'is not pending' do
      it 'returns that the migration is not pending' do
        migration = FactoryGirl.create(:running_migration)
        expect(migration.pending?).to eq(false)
      end
    end
  end

  describe 'editable?' do
    context 'is editable' do
      it 'returns that the migration is editable' do
        migration = FactoryGirl.create(:pending_migration)
        expect(migration.editable?).to eq(true)
      end
    end

    context 'is not editable' do
      it 'returns that the migration is not editable' do
        migration = FactoryGirl.create(:running_migration)
        expect(migration.editable?).to eq(false)
      end
    end
  end

  describe 'cluster_running_maxed_out?' do
    it 'returns false if the mig is a create or drop' do
      migration = FactoryGirl.create(:running_migration)
      migration.ddl_statement = "create table t like z"
      FactoryGirl.create(:running_migration)
      expect(migration.cluster_running_maxed_out?).to eq(false)
    end

    it 'returns true if the mig is an alter and cluster is maxed out' do
      migration = FactoryGirl.create(:start_migration)
      FactoryGirl.create(:running_migration)
      expect(migration.cluster_running_maxed_out?).to eq(true)
    end

    it 'returns false if the mig is an alter and cluster is not maxed out' do
      migration = FactoryGirl.create(:start_migration)
      migration2 = FactoryGirl.create(:running_migration)
      migration2.ddl_statement = "create table t like z"
      migration2.save
      expect(migration.cluster_running_maxed_out?).to eq(false)
    end
  end

  describe 'approve!' do
    before (:each) do
      @current_user_name = "developer"
    end

    context 'is on approve step' do
      it 'approves the migration' do
        migration = FactoryGirl.create(:approval_migration)
        expect(migration.approve!(@current_user_name, 1, migration.lock_version)).to eq(true)
        migration.reload
        expect(migration.approved_by).to eq(@current_user_name)
        expect(migration.runtype).to eq(1)
        expect(migration.approved_at.utc.to_i).to be_within(2).of Time.now.to_i
      end
    end

    context 'is not on approve step' do
      it 'does not approve the migration' do
        migration = FactoryGirl.create(:canceled_migration)
        expect(migration.approve!(@current_user_name, 1, migration.lock_version)).to eq(false)
        migration.reload
        expect(migration.approved_by).to eq(nil)
        expect(migration.runtype).to eq(0)
        expect(migration.approved_at).to eq (nil)
      end
    end
  end

  describe 'unapprove!' do
    before (:each) do
      @current_user_name = "developer"
    end

    context 'is on start step' do
      it 'unapproves the migration' do
        migration = FactoryGirl.create(:start_migration)
        expect(migration.approved_by).not_to eq(nil)
        expect(migration.approved_at).not_to eq (nil)
        expect(migration.unapprove!(migration.lock_version)).to eq(true)
        starting_lock_version = migration.lock_version
        migration.reload
        expect(migration.approved_by).to eq(nil)
        expect(migration.approved_at).to eq (nil)
        expect(migration.status).to eq(Migration.status_groups[:awaiting_approval])
        expect(migration.lock_version).to eq(starting_lock_version + 1)
      end
    end

    context 'is not on start step' do
      it 'does not unapprove the migration' do
        migration = FactoryGirl.create(:approval_migration)
        starting_status = migration.status
        expect(migration.unapprove!(migration.lock_version)).to eq(false)
        migration.reload
        expect(migration.status).to eq(starting_status)
      end
    end
  end

  describe 'start!' do
    context 'is on start step cluster not maxed out' do
      it 'sets the start time of the migration' do
        migration = FactoryGirl.create(:start_migration)
        expect(migration.started_at).to eq(nil)
        expect(migration.start!(migration.lock_version)).to eq([true, false])
        migration.reload
        expect(migration.started_at.utc.to_i).to be_within(2).of Time.now.to_i
      end

      it 'sets the migration as uneditable' do
        migration = FactoryGirl.create(:start_migration)
        expect(migration.editable).to eq(true)
        expect(migration.start!(migration.lock_version)).to eq([true, false])
        migration.reload
        expect(migration.editable).to eq(false)
      end

      it 'stages the migration and puts it in the copy step' do
        migration = FactoryGirl.create(:start_migration)
        expect(migration.staged).to eq(false)
        expect(migration.start!(migration.lock_version)).to eq([true, false])
        migration.reload
        expect(migration.staged).to eq(true)
        expect(migration.status).to eq(Migration.status_groups[:copy_in_progress])
      end
    end

    context 'auto_run is true' do
      it 'sets the auto_run field on the migration to true or false (true here)' do
        migration = FactoryGirl.create(:start_migration)
        expect(migration.auto_run).to eq(false)
        expect(migration.start!(migration.lock_version, true)).to eq([true, false])
        migration.reload
        expect(migration.auto_run).to eq(true)
      end
    end

    context 'is on start step cluster is maxed out ddl is alter' do
      it 'does not set the start time of the migration' do
        migration = FactoryGirl.create(:start_migration)
        FactoryGirl.create(:running_migration)
        expect(migration.started_at).to eq(nil)
        expect(migration.start!(migration.lock_version)).to eq([false, true])
        migration.reload
        expect(migration.started_at).to eq(nil)
      end
    end

    context 'is on start step cluster is maxed out ddl is create' do
      it 'sets the start time of the migration' do
        migration = FactoryGirl.create(:start_migration)
        migration.ddl_statement = "create table t like z"
        FactoryGirl.create(:running_migration)
        expect(migration.started_at).to eq(nil)
        expect(migration.start!(migration.lock_version)).to eq([true, false])
        migration.reload
        expect(migration.started_at.utc.to_i).to be_within(2).of Time.now.to_i
      end
    end

    context 'is not on start step' do
      it 'does not set the start time of the migration' do
        migration = FactoryGirl.create(:approval_migration)
        expect(migration.start!(migration.lock_version)).to eq([false, false])
        migration.reload
        expect(migration.started_at).to eq(nil)
      end
    end
  end

  describe 'enqueue!' do
    context 'is on an enqueueable step' do
      it 'enqueues the migration' do
        migration = FactoryGirl.create(:start_migration)
        expect(migration.enqueue!(migration.lock_version)).to eq(true)
        migration.reload
        expect(migration.auto_run).to eq (true)
        expect(migration.status).to eq(Migration.status_groups[:enqueued])
      end

      it 'sets auto_run to true' do
        migration = FactoryGirl.create(:start_migration)
        expect(migration.auto_run).to eq (false)
        expect(migration.enqueue!(migration.lock_version)).to eq(true)
        migration.reload
        expect(migration.auto_run).to eq (true)
      end
    end

    context 'is not on an enqueueable step' do
      it 'does not enqueue the migration' do
        migration = FactoryGirl.create(:approval_migration)
        starting_status = migration.status
        expect(migration.enqueue!(migration.lock_version)).to eq(false)
        migration.reload
        expect(migration.status).to eq(starting_status)
      end
    end
  end

  describe 'dequeue!' do
    context 'is on a dequeueable step' do
      it 'dequeues the migration' do
        migration = FactoryGirl.create(:enqueued_migration)
        expect(migration.auto_run).to eq (true)
        expect(migration.dequeue!(migration.lock_version)).to eq(true)
        migration.reload
        expect(migration.auto_run).to eq (false)
        expect(migration.status).to eq(Migration.status_groups[:awaiting_start])
      end

      it 'sets auto_run to false' do
        migration = FactoryGirl.create(:enqueued_migration)
        expect(migration.auto_run).to eq (true)
        expect(migration.dequeue!(migration.lock_version)).to eq(true)
        migration.reload
        expect(migration.auto_run).to eq (false)
      end
    end

    context 'is not on a dequeueable step' do
      it 'does not dequeue the migration' do
        migration = FactoryGirl.create(:approval_migration)
        starting_status = migration.status
        expect(migration.dequeue!(migration.lock_version)).to eq(false)
        migration.reload
        expect(migration.status).to eq(starting_status)
      end
    end
  end

  describe 'pause!' do
    context 'is on the copy step' do
      it 'puts the migration in the pausing step' do
        migration = FactoryGirl.create(:copy_migration)
        expect(migration.pause!).to eq(true)
        migration.reload
        expect(migration.staged).to eq(true)
        expect(migration.status).to eq(Migration.status_groups[:pausing])
      end

      it 'sets auto_run to false' do
        migration = FactoryGirl.create(:copy_migration, :auto_run => true)
        expect(migration.auto_run).to eq (true)
        expect(migration.pause!).to eq(true)
        migration.reload
        expect(migration.auto_run).to eq (false)
      end
    end

    context 'is not on the copy step' do
      it 'does not put the migration in the pausing step' do
        migration = FactoryGirl.create(:approval_migration)
        starting_status = migration.status
        expect(migration.pause!).to eq(false)
        migration.reload
        expect(migration.status).to eq(starting_status)
      end
    end
  end

  describe 'rename!' do
    context 'is on the awaiting rename step' do
      it 'puts the migration in the rename in progress step' do
        migration = FactoryGirl.create(:awaiting_rename_migration)
        expect(migration.rename!(migration.lock_version)).to eq(true)
        migration.reload
        expect(migration.staged).to eq(true)
        expect(migration.status).to eq(Migration.status_groups[:rename_in_progress])
      end
    end

    context 'is not on the copy step' do
      it 'does not put the migration in the pausing step' do
        migration = FactoryGirl.create(:approval_migration)
        starting_status = migration.status
        expect(migration.rename!(migration.lock_version)).to eq(false)
        migration.reload
        expect(migration.status).to eq(starting_status)
      end
    end
  end

  describe 'resume!' do
    context 'is on a resumable step' do
      it 'puts the migration in the copy step' do
        migration = FactoryGirl.create(:resumable_migration)
        migration.error_message = "there was a problem"; migration.save
        expect(migration.resume!(migration.lock_version)).to eq(true)
        migration.reload
        expect(migration.staged).to eq(true)
        expect(migration.status).to eq(Migration.status_groups[:copy_in_progress])
        expect(migration.error_message).to eq(nil)
      end
    end

    context 'is not on a resumeable step' do
      it 'does not put the migration in the pausing step' do
        migration = FactoryGirl.create(:approval_migration)
        migration.error_message = "there was a problem"; migration.save
        starting_status = migration.status
        expect(migration.resume!(migration.lock_version)).to eq(false)
        migration.reload
        expect(migration.status).to eq(starting_status)
        expect(migration.error_message).to eq("there was a problem")
      end
    end
  end

  describe 'cancel!' do
    context 'is on a cancel step' do
      before (:each) do
        @migration = FactoryGirl.create(:cancelable_migration)
      end

      it 'cancels the migration' do
        expect(@migration.status).to_not eq(Migration.status_groups[:canceled])
        expect(@migration.cancel!).to eq(true)
        @migration.reload
        expect(@migration.status).to eq(Migration.status_groups[:canceled])
      end

      it 'stages the migration' do
        @migration.cancel!
        expect(@migration.staged).to eq(true)
      end
    end

    context 'is not on a cancel step' do
      it 'does not cancel the migration' do
        migration = FactoryGirl.create(:noncancelable_migration)
        starting_status = migration.status
        expect(migration.cancel!).to eq(false)
        migration.reload
        expect(migration.status).to eq(starting_status)
      end
    end
  end

  describe 'complete!' do
    it 'completes the migration' do
      migration = FactoryGirl.create(:running_migration)
      expect(migration.completed_at).to eq(nil)
      expect(migration.complete!).to eq(true)
      migration.reload
      expect(migration.status).to eq(Migration.status_groups[:completed])
      expect(migration.completed_at.utc.to_i).to be_within(2).of Time.now.to_i
    end
  end

  describe 'fail!' do
    it 'fails the migration' do
      migration = FactoryGirl.create(:human_migration)
      expect(migration.status).to_not eq(Migration.status_groups[:failed])
      expect(migration.error_message).to eq(nil)
      expect(migration.fail!("Error message.")).to eq(true)
      migration.reload
      expect(migration.status).to eq(Migration.status_groups[:failed])
      expect(migration.error_message).to eq("Error message.")
    end

    it 'sets auto_run to false' do
      migration = FactoryGirl.create(:human_migration, :auto_run => true)
      expect(migration.auto_run).to eq (true)
      expect(migration.fail!("Error message.")).to eq(true)
      migration.reload
      expect(migration.auto_run).to eq (false)
    end
  end

  describe 'error!' do
    context 'is on the copy step' do
      it 'errors the migration' do
        migration = FactoryGirl.create(:copy_migration)
        expect(migration.error_message).to eq(nil)
        expect(migration.error!("Error message.")).to eq(true)
        migration.reload
        expect(migration.status).to eq(Migration.status_groups[:error])
        expect(migration.error_message).to eq("Error message.")
      end

      it 'sets auto_run to false' do
        migration = FactoryGirl.create(:copy_migration, :auto_run => true)
        expect(migration.auto_run).to eq (true)
        expect(migration.error!("Error message.")).to eq(true)
        migration.reload
        expect(migration.auto_run).to eq (false)
      end
    end

    context 'is not on the copy step' do
      it 'does not error the migration' do
        migration = FactoryGirl.create(:approval_migration)
        starting_status = migration.status
        expect(migration.error!("Error message.")).to eq(false)
        migration.reload
        expect(migration.status).to eq(starting_status)
        expect(migration.error_message).to eq(nil)
      end
    end
  end

  describe 'delete!' do
    context 'is on a deletable step' do
      it 'deletes the migration' do
        migration = FactoryGirl.create(:approval_migration)
        expect(migration.delete!(migration.lock_version)).to eq(true)
        expect(Migration.exists?(migration.id)).to eq(false)
      end
    end

    context 'is not on a deletable step' do
      it 'does not delete the migration' do
        migration = FactoryGirl.create(:copy_migration)
        expect(migration.delete!(migration.lock_version)).to eq(false)
        expect(Migration.exists?(migration.id)).to eq(true)
      end
    end
  end

  describe 'offer!' do
    context 'is on a offerable step' do
      it 'offers the migration' do
        migration = FactoryGirl.create(:copy_migration, staged: false)
        expect(migration.offer!).to eq(true)
        migration.reload
        expect(migration.staged).to eq(true)
      end
    end

    context 'is not on a offerable step' do
      it 'does not offer the migration' do
        migration = FactoryGirl.create(:approval_migration, staged: false)
        expect(migration.offer!).to eq(false)
        migration.reload
        expect(migration.staged).to eq(false)
      end
    end
  end

  describe 'unpin_run_host!' do
    it 'makes the migration run_host nil' do
      migration = FactoryGirl.create(:migration, run_host: "host")
      expect(migration.unpin_run_host!).to eq(true)
      migration.reload
      expect(migration.run_host).to be_nil
    end
  end

  describe 'unstage!' do
    it 'unstages the migration' do
      migration = FactoryGirl.create(:canceled_migration)
      expect(migration.staged).to eq(true)
      migration.unstage!
      expect(migration.staged).to eq(false)
    end
  end

  describe 'increment_status!' do
    it 'incrememnts the status of the migration' do
      migration = FactoryGirl.create(:human_migration)
      starting_status = migration.status
      migration.increment_status!
      migration.reload
      expect(migration.status).to eq(starting_status + 1)
    end
  end

  describe 'next_step_machine!' do
    context 'is on a machine step' do
      it 'increments the status of the migration' do
        migration = FactoryGirl.create(:machine_migration)
        expect(migration).to receive(:increment_status!)
        migration.next_step_machine!
      end

      it 'does not increment the status of the migration because it is staged' do
        migration = FactoryGirl.create(:machine_migration, :staged => true)
        expect(migration).to_not receive(:increment_status!)
        migration.next_step_machine!
      end
    end

    context 'is not on a machine step' do
      it 'does not increment the status of the migration' do
        migration = FactoryGirl.create(:human_migration)
        expect(migration).to_not receive(:increment_status!)
        migration.next_step_machine!
      end
    end
  end

  describe 'small_enough_for_short_run?' do
    it 'is not because table_rows_start is null' do
      migration = FactoryGirl.create(:approval_migration)
      expect(migration.small_enough_for_short_run?).to eq(false)
    end

    it 'is not because there are too many rows' do
      migration = FactoryGirl.create(:approval_migration,
                                     :table_rows_start => Migration.small_table_row_limit + 1)
      expect(migration.small_enough_for_short_run?).to eq(false)
    end

    it 'is not because meta_request_id is not null' do
      migration = FactoryGirl.create(:approval_migration, :meta_request_id => 1,
                                     :table_rows_start => Migration.small_table_row_limit - 1)
      expect(migration.small_enough_for_short_run?).to eq(false)
    end

    it 'is small enough' do
      migration = FactoryGirl.create(:approval_migration,
                                     :table_rows_start => Migration.small_table_row_limit - 1)
      expect(migration.small_enough_for_short_run?).to eq(true)
    end
  end

  describe 'authorized_actions' do
    it 'random case 1 (authorized approver for a mig awaiting approval)' do
      migration = FactoryGirl.create(:approval_migration)
      output = migration.authorized_actions(
        Migration.types[:run][:maybeshort],
        Migration.types[:action][:alter],
        false, true, false, true)
      expect(output).to eq([:approve_long, :delete])
    end

    it 'random case 2 (authorized admin for a mig awaiting approval)' do
      migration = FactoryGirl.create(:approval_migration)
      output = migration.authorized_actions(
        Migration.types[:run][:maybeshort],
        Migration.types[:action][:alter],
        true, false, false, true)
      expect(output).to eq([:approve_long, :approve_short, :delete])
    end

    it 'random case 3 (authorized admin for a mig awaiting approval that is small_enough_for_short_run)' do
      migration = FactoryGirl.create(:approval_migration, :table_rows_start => 4031)
      output = migration.authorized_actions(
        Migration.types[:run][:maybeshort],
        Migration.types[:action][:alter],
        true, false, false, true)
      expect(output).to eq([:approve_short, :delete])
    end

    it 'random case 4 (authorized admin for a mig awaiting approval that is not small_enough_for_short_run)' do
      migration = FactoryGirl.create(:approval_migration, :table_rows_start => 11000)
      output = migration.authorized_actions(
        Migration.types[:run][:maybeshort],
        Migration.types[:action][:alter],
        true, false, false, true)
      expect(output).to eq([:approve_long, :approve_short, :delete])
    end

    it 'random case 5 (no authorization for a mig awaiting approval)' do
      migration = FactoryGirl.create(:approval_migration)
      output = migration.authorized_actions(
        Migration.types[:run][:maybeshort],
        Migration.types[:action][:alter],
        false, false, false, false)
      expect(output).to eq([])
    end

    it 'random case 6 (requestor for a mig awaiting approval)' do
      migration = FactoryGirl.create(:approval_migration)
      output = migration.authorized_actions(
        Migration.types[:run][:maybeshort],
        Migration.types[:action][:alter],
        false, false, true, false)
      expect(output).to eq([:delete])
    end

    it 'random case 7 (different actions for different run_actions)' do
      migration = FactoryGirl.create(:copy_migration)
      output = migration.authorized_actions(
        Migration.types[:run][:long],
        Migration.types[:action][:alter],
        true, true, true, true)
      expect(output).to eq([:pause, :cancel])
    end
  end
end
