class AdminController < ApplicationController
  before_action :require_admin
  def index
    @cluster_names = Migration.select(:cluster_name).map(&:cluster_name).uniq.sort
  end

  def refresh_filed_chart
    weeks_requested = params[:weeks].to_i
    migrations_filed = {}
    migrations_completed = {}
    formatted_dates = {}
    keys = {}

    if weeks_requested == 0 #gets all time data
      migrations_filed = Migration.where("created_at IS NOT NULL")
        .group("DATE_FORMAT(created_at, '%Y-%m')").order("created_at").count
      migrations_completed = Migration.where("completed_at IS NOT NULL")
        .group("DATE_FORMAT(completed_at, '%Y-%m')").order("completed_at").count
      if migrations_filed.first
        first_date = Date.strptime(migrations_filed.first[0], '%Y-%m')
      else
        first_date = Date.today
      end

      today = Date.today
      number_months = (today.year * 12 + today.month) - (first_date.year * 12 + first_date.month) + 1

      keys = keys_by_month(number_months)
      formatted_dates = formatted_dates_by_month(number_months)
    elsif weeks_requested <= 4 #group data by days if less than 4 weeks requested
      migrations_filed = Migration.where("created_at > ?",
        (weeks_requested).weeks.ago.to_s.split.first)
        .group("DATE_FORMAT(created_at, '%Y-%m-%d')").order("created_at").count
      migrations_completed = Migration.where("completed_at > ?",
        (weeks_requested).weeks.ago.to_s.split.first)
        .group("DATE_FORMAT(completed_at, '%Y-%m-%d')").order("completed_at").count
      keys = keys_by_day(weeks_requested*7)
      formatted_dates = formatted_dates_by_day(weeks_requested*7)
    else
      migrations_filed = Migration.where("created_at > ?",
        weeks_requested.weeks.ago.beginning_of_week(:sunday).to_s.split.first)
        .group("DATE_FORMAT(created_at, '%Y-%U')").order("created_at").count
      migrations_completed = Migration.where("completed_at > ?",
        weeks_requested.weeks.ago.beginning_of_week(:sunday).to_s.split.first)
        .group("DATE_FORMAT(completed_at, '%Y-%U')").order("completed_at").count
      keys = keys_by_week(weeks_requested)
      formatted_dates = formatted_dates_by_week(weeks_requested)
    end

    migrations_filed = fill_zero_data(migrations_filed, keys)
    migrations_completed = fill_zero_data(migrations_completed, keys)

    render json: {
      "migrations_filed": migrations_filed.values,
      "migrations_completed": migrations_completed.values,
      "categories": formatted_dates
    }
  end

  def refresh_approval_time_chart
    weeks_requested = params[:weeks].to_i
    average_approval_times = {}
    formatted_dates = {}
    keys = {}

    if weeks_requested == 0
      average_approval_times = Migration.where("approved_at IS NOT NULL AND created_at IS NOT NULL")
        .group("DATE_FORMAT(created_at, '%Y-%m')")
        .order("created_at").average("TIMESTAMPDIFF(SECOND, created_at, approved_at)")
      if average_approval_times.first
        first_date = Date.strptime(average_approval_times.first[0], '%Y-%m')
      else
        first_date = Date.today
      end
      today = Date.today
      number_months = (today.year*12 + today.month) - (first_date.year*12 + first_date.month) + 1
      keys = keys_by_month(number_months)
      formatted_dates = formatted_dates_by_month(number_months)
    elsif weeks_requested <= 4
      average_approval_times = Migration.where("approved_at IS NOT NULL AND created_at > ?",
        (weeks_requested).weeks.ago.to_s.split.first)
        .group("DATE_FORMAT(created_at, '%Y-%m-%d')").order("created_at")
        .average("TIMESTAMPDIFF(SECOND, created_at, approved_at)")
      keys = keys_by_day(weeks_requested*7)
      formatted_dates = formatted_dates_by_day(weeks_requested*7)
    else
      average_approval_times = Migration.where("approved_at IS NOT NULL AND created_at > ?",
        weeks_requested.weeks.ago.beginning_of_week(:sunday).to_s.split.first)
        .group("DATE_FORMAT(created_at, '%Y-%U')").order("created_at")
        .average("TIMESTAMPDIFF(SECOND, created_at, approved_at)")
      keys = keys_by_week(weeks_requested)
      formatted_dates = formatted_dates_by_week(weeks_requested)
    end
    average_approval_times.map {|k,time| average_approval_times[k] = (time / 3600).to_f.round(1)}
    average_approval_times = remove_zero_data(average_approval_times, keys)

    render json: {
      "average_approval_times": average_approval_times.values,
      "categories": formatted_dates
    }
  end

  def refresh_cluster_metrics
    cluster = params[:cluster]

    migrations = {}

    Migration.where("cluster_name = ? AND completed_at IS NOT NULL AND started_at IS NOT NULL", cluster)
    .each do |migration|
      begin
        table_name = OscParser.new.parse(migration.ddl_statement)[:table]
      rescue
        next # skip unparsable statements
      end
      alter_time = migration.completed_at - migration.started_at

      if !migrations.has_key?(migration.database)
        migrations[migration.database] = {}
      end

      db = migrations[migration.database]

      if db.has_key?(table_name)
        table = db[table_name]
        table[:times_altered] += 1
        table[:average_alter_time] = (table[:average_alter_time] * (table[:times_altered] - 1) + alter_time) / table[:times_altered]
        table[:max_alter_time] = [table[:max_alter_time], alter_time].max
        table[:min_alter_time] = [table[:min_alter_time], alter_time].min
      else
        db[table_name] = {
          :times_altered => 1,
          :average_alter_time => alter_time,
          :max_alter_time => alter_time,
          :min_alter_time => alter_time
        }
      end
    end

    migrations.each do |k, database|
      migrations[k] = database.sort_by {|k,v| v[:average_alter_time]}.reverse.to_h
    end

    render json: migrations
  end

  private
  
  def keys_by_month(number_months)
    number_months.times.map {|x| (number_months.months.ago + (x + 1).months).strftime("%Y-%m")}
  end

  def keys_by_week(number_weeks)
    number_weeks.times.map {|x| (number_weeks.weeks.ago.beginning_of_week(:sunday) + (x + 1).weeks).strftime("%Y-%U")}
  end

  def keys_by_day(number_days)
    number_days.times.map {|x| (number_days.days.ago + (x + 1).days).strftime("%Y-%m-%d")}
  end

  def formatted_dates_by_month(number_months)
    number_months.times.map{|x| (number_months.months.ago + (x + 1).months).strftime("%m/%Y")}
  end

  def formatted_dates_by_week(number_weeks)
    number_weeks.times.map {|x| (number_weeks.weeks.ago.beginning_of_week(:sunday) + (x + 1).weeks).strftime("%D")}
  end

  def formatted_dates_by_day(number_days)
    number_days.times.map{|x| (number_days.days.ago + (x + 1).days).strftime("%a, %m/%d")}
  end

  def fill_zero_data(data, keys)
    result = {}
    keys.each do |k|
      result[k] = data.fetch(k, 0)
    end
    result
  end

  def remove_zero_data(data, keys)
    result = {}
    keys.each do |k|
      if data[k] == 0 || data[k] == nil
        result[k] = nil
      else
        result[k] = data[k]
      end
    end
    result
  end
end