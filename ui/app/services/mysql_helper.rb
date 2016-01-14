# The mysql helper allows the shift ui to connect to databases it's going
# to alter. It only needs read-only permissions since the functionality here is
# soley for inspecting existing schema and mysql settings. The credentials that
# provide access for the mysql helper are in config/environments/*

require 'mysql2'

class MysqlError < StandardError
end

class MysqlHelper
  def initialize(cluster_name)
    @cluster = Cluster.find_by(:name => cluster_name)
    @host =
      if Rails.env.staging? || Rails.env.production?
        @cluster.rw_host
      elsif Rails.env.test? || Rails.env.development?
        'localhost'
      end

    # obsolete cluster

    raise MysqlError, 'host not found' if @host.nil?

    begin
      @client =
        Mysql2::Client.new(
          Rails.application.config.x.mysql_helper.db_config.merge({
          :host => @host,
          :connect_timeout => 5})
        )
    rescue Mysql2::Error => e
      raise MysqlError, "error in connection: #{e}"
    end
  end

  def close
    @client.close
  end

  def normalize_table(name)
    @client.escape(name)
  end

  def normalize_database(name)
    @client.escape(Rails.env.development? ? name.gsub(/__.*/, '') : name)
  end

  def table_exists?(mode, database, table)
    database = normalize_database(database)
    table = normalize_table(table)
    row = @client.query("SELECT COUNT(*) AS count FROM information_schema.#{mode}s
                         WHERE table_schema='#{database}'
                         AND table_name='#{table}' LIMIT 1").first
    row['count'] != 0
  end

  def databases
    results = @client.query("SHOW DATABASES").map { |row| row['Database'] }
    results - Rails.application.config.x.mysql_helper.db_blacklist
  end

  def self.safe_databases(cluster_name)
    begin
      MysqlHelper.new(cluster_name).databases
    rescue
      []
    end
  end

  def row_format(database, table)
    database = normalize_database(database)
    table = normalize_table(table)
    rows = @client.query("SELECT ROW_FORMAT FROM information_schema.tables
                          WHERE table_schema='#{database}'
                          AND table_name='#{table}' LIMIT 1")
    if rows.count != 0
      rows.first['ROW_FORMAT']
    else
      raise MysqlError, "table #{table} not exists!"
    end
  end

  def columns(database, table)
    database = normalize_database(database)
    table = normalize_table(table)
    rows = @client.query("SHOW COLUMNS FROM `#{database}`.`#{table}`")
    ret = {}
    rows.each do |row|
      ret[row['Field']] = {
        type: row['Type']
      }
    end
    ret
  end

  def has_referenced_foreign_keys?(database, table)
    database = normalize_database(database)
    table = normalize_table(table)
    query = "SELECT COUNT(*) AS count
             FROM information_schema.key_column_usage
             WHERE referenced_table_schema='#{database}'
             AND referenced_table_name='#{table}'"
    @client.query(query).first['count'] != 0
  end

  def foreign_keys(database, table)
    database = normalize_database(database)
    table = normalize_table(table)
    query = "SELECT CONSTRAINT_NAME
             FROM information_schema.key_column_usage
             WHERE table_schema='#{database}'
             AND table_name='#{table}'
             AND REFERENCED_TABLE_SCHEMA IS NOT NULL"
    @client.query(query).map { |fk| fk['CONSTRAINT_NAME'] }
  end

  def version
    @client.query('SELECT VERSION() as version')
      .first['version'].split('.').take(2).join('.') # 5.6, 5.5, 11.123a, etc.
  end

  def avoid_temporal_upgrade?
    if version == '5.6' || version == '5.7'
      begin
        @client.query('SELECT @@avoid_temporal_upgrade as val').first['val'] == 1
      rescue
        true
      end
    else
      true
    end
  end
end
