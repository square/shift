require 'rufus-scheduler'

scheduler = Rufus::Scheduler.singleton

# run migrations that have been started with a bulk action
scheduler.every '15s' do
  # select the oldest migration (by id) for each cluster that is queued up to start
  start_subquery = subquery = Migration.select('MIN(id) as id').
    where(:status => Migration.status_groups["enqueued"], :auto_run => 1).group(:cluster_name).to_sql
  queued_start_migrations = Migration.joins("JOIN (#{start_subquery}) m on migrations.id = m.id")

  # select the oldest migration (by id) for each cluster that is waiting to be renamed
  rename_subquery = subquery = Migration.select('MIN(id) as id').
    where(:status => Migration.status_groups["awaiting_rename"], :auto_run => 1).group(:cluster_name).to_sql
  queued_rename_migrations = Migration.joins("JOIN (#{rename_subquery}) m on migrations.id = m.id")

  queued_start_migrations.each do |m|
    $stderr.puts "trying to start migration #{m.id}"
    m.start!(m.lock_version, auto_run = true)
  end

  queued_rename_migrations.each do |m|
    $stderr.puts "trying to rename migration #{m.id}"
    m.rename!(m.lock_version)
  end
end
