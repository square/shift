require 'active_model'

module Form
  class EditMigrationRequest < ::Form::MigrationRequest
    def initialize(dao, params = {})
      @dao = dao

      ATTRIBUTES.each do |attr|
        if params.has_key?(attr.to_s) && mutable?(attr.to_s)
          self.send("#{attr}=", params[attr.to_s])
        elsif dao.has_attribute?(attr.to_s)
          # accesses ActiveRecord attributes
          self.send("#{attr}=", dao[attr.to_s])
        else
          # accesses non persistent instance variables (custom options)
          self.send("#{attr}=", dao.instance_variable_get("@#{attr.to_s}"))
        end
      end
    end

    def save
      return false unless valid?

      dao.send(:update_attributes,
        cluster_name: cluster_name,
        database: database,
        ddl_statement: ddl_statement,
        pr_url: pr_url,
        requestor: requestor,
        final_insert: final_insert,
        status: 0,
        staged: 1,
        table_rows_start: nil,
        table_size_start: nil,
        index_size_start: nil,
        approved_by: nil,
        approved_at: nil,
        error_message: nil,
        runtype: Migration.types[:run][:undecided],
        initial_runtype: initial_runtype,
        max_threads_running: max_threads_running,
        max_replication_lag: max_replication_lag,
        config_path: config_path,
        recursion_method: recursion_method,
      )
    end

    def editable?
      dao.editable
    end

    private

    def mutable?(attr)
      %w(cluster_name database table ddl_statement pr_url requestor final_insert max_threads_running max_replication_lag config_path recursion_method).include?(attr)
    end
  end
end
