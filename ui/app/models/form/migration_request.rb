require 'active_model'

module Form

  class SQLValidator < ActiveModel::Validator
    def validate(record)
      # let's not validate if something else is wrong
      return unless record.errors[:base].empty?
      if record.ddl_statement.nil?
        # FIXME: this is just to make the test passed
        # actually record.ddl_statement will always be a string
        record.errors[:base] << "DDL statement is nil"; return
      end
      parser = OscParser.new

      begin
        mysql = MysqlHelper.new(record.cluster_name)
      rescue => e
        record.errors[:base] << "Connection error (#{e.message})"
        return
      end

      checkers = {
        table_exists: lambda do |mode, table|
          mysql.table_exists? mode, record.database, table
        end,
        get_row_format: lambda do |table|
          mysql.row_format(record.database, table).upcase
        end,
        get_columns: lambda do |table|
          mysql.columns record.database, table
        end,
        has_referenced_foreign_keys: lambda do |table|
          mysql.has_referenced_foreign_keys? record.database, table
        end,
        get_foreign_keys: lambda do |table|
          mysql.foreign_keys record.database, table
        end,
        avoid_temporal_upgrade?: lambda do
          mysql.avoid_temporal_upgrade?
        end
      }
      parser.merge_checkers! checkers
      begin
        parsed = parser.parse record.ddl_statement
        # save the initial runtype (needed for bulk approvals)
        record.send("initial_runtype=", Migration.types[:run][parsed[:run]])
      rescue => e
        record.errors[:base] << "DDL statement is invalid (error: #{e.message})"
      end
    end
  end

  # Base class for all Migration forms. See subclasses for usage.
  class MigrationRequest
    attr_accessor :dao

    extend ActiveModel::Naming
    include ActiveModel::Validations

    validates_presence_of :cluster_name
    validates_presence_of :database
    validates_presence_of :ddl_statement
    validates_presence_of :pr_url
    validates_numericality_of :max_threads_running, greater_than: 0
    validates_numericality_of :max_replication_lag, greater_than: 0
    # don't allow semicolons anywhere
    validates_format_of :database, :with => /\A[^;]+\Z/

    validates_with SQLValidator, fields: [:ddl_statement]
    validates_format_of :final_insert, :with => /\A(?i)(INSERT\s+INTO\s+)[^;]+\Z/i, :allow_blank => true

    def self.all_clusters
      @all_clusters = Cluster.all
    end

    validates :cluster_name, inclusion: {in: proc {all_clusters.collect(&:name)}}

    def to_param
      dao.to_param
    end

    # TODO: find a better way to add attributes, right now you have to add stuff in like 10 places
    ATTRIBUTES = [
      :cluster_name,
      :database,
      :table,
      :ddl_statement,
      :pr_url,
      :max_threads_running,
      :max_replication_lag,
      :config_path,
      :recursion_method,
      :requestor,
      :final_insert,
      :meta_request_id,
      :initial_runtype,
    ]
    attr_accessor *ATTRIBUTES

    def to_key
      dao ? dao.to_key : nil
    end

    def persisted?
      !!dao
    end
  end
end
