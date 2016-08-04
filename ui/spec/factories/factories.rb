FactoryGirl.define do
  statuses = Migration.status_groups

  factory :cluster do
    sequence :id do |n|
      n
    end
    name "appname-001"
    rw_host "rw.host.name"
    port 3306
    app "appname"
  end

  factory :owner do
    sequence :id do |n|
      n
    end
    cluster_name "appname-001"
    username "developer"
  end

  factory :migration do
    sequence :id do |n|
      n
    end
    cluster_name "appname-001"
    database "testdb"
    ddl_statement "alter table test_table drop column c1"
    pr_url "github.com/pr"
    requestor "developer"
    max_threads_running "200"
    max_replication_lag "1"
    lock_version = 4
  end

  factory :meta_request do
    sequence :id do |n|
      n
    end
    ddl_statement "alter table test_table drop column c1"
    pr_url "github.com/pr"
    final_insert nil
    requestor "developer"
    max_threads_running "200"
    max_replication_lag "1"
  end

  factory :shift_file do
    sequence :id do |n|
      n
    end
  end


  factory :pending_migration, parent: :migration do
    status statuses[:pending].sample
  end

  factory :running_migration, parent: :migration do
    status statuses[:running].sample
    editable false
  end

  factory :preparing_migration, parent: :migration do
    status statuses[:preparing]
  end

  factory :completed_migration, parent: :migration do
    status statuses[:completed]
  end

  factory :canceled_migration, parent: :migration do
    status statuses[:canceled]
  end

  factory :failed_migration, parent: :migration do
    status statuses[:failed]
  end

  factory :deletable_migration, parent: :migration do
    status statuses[:deletable].sample
  end

  factory :undeletable_migration, parent: :migration do
    status (statuses[:all] - statuses[:deletable]).sample
    requestor 'random_user'
  end

  factory :human_migration, parent: :migration do
    status statuses[:human].sample
  end

  factory :machine_migration, parent: :migration do
    status statuses[:machine].sample
    staged false
  end

  factory :approval_migration, parent: :migration do
    status statuses[:awaiting_approval]
    staged false
  end

  factory :copy_migration, parent: :migration do
    status statuses[:copy_in_progress]
  end

  factory :awaiting_rename_migration, parent: :migration do
    status statuses[:awaiting_rename]
  end

  factory :start_migration, parent: :migration do
    status statuses[:awaiting_start]
    approved_by 'admin'
    approved_at '2014-01-01 00:00:00'
    staged false
  end

  factory :enqueued_migration, parent: :migration do
    auto_run true
    status statuses[:enqueued]
  end

  factory :resumable_migration, parent: :migration do
    status statuses[:resumable].sample
  end

  factory :cancelable_migration, parent: :migration do
    status statuses[:cancelable].sample
  end

  factory :noncancelable_migration, parent: :migration do
    status (statuses[:all] - statuses[:cancelable]).sample
  end

  factory :staged_migration, parent: :migration do
    status statuses[:machine].sample
    staged true
  end

  factory :staged_run_migration, parent: :migration do
    status (statuses[:machine] - [statuses[:preparing]] - [statuses[:canceled]]).sample
    staged true
  end

  factory :meta_request_without_migrations, parent: :meta_request do
    migrations []
  end

  factory :meta_request_with_migrations, parent: :meta_request do
    after(:create) do |meta_request|
      create(:migration, meta_request_id: meta_request.id)
    end
  end
end
