require 'active_model'

module Form
  class NewMigrationRequest < ::Form::MigrationRequest
    def initialize(params = {})
      ATTRIBUTES.each do |attr|
        if params.has_key?(attr.to_s)
          self.send("#{attr}=", params[attr.to_s])
        end
      end
    end

    def save
      return false if invalid?
      self.dao = ::Migration.create!(
        cluster_name: cluster_name,
        database: database,
        ddl_statement: ddl_statement,
        pr_url: pr_url,
        requestor: requestor,
        final_insert: final_insert,
        meta_request_id: meta_request_id,
        runtype: Migration.types[:run][:undecided],
        initial_runtype: initial_runtype,
      )
      true
    end
  end
end
