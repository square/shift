class MetaRequestsController < ApplicationController
  def index
    @meta_requests = MetaRequest.all().order("created_at DESC").page(params[:page])
    @count = MetaRequest.count
  end

  def show
    @meta_request = MetaRequest.find(params[:id])
    @statuses = Statuses.all()
    begin
      result = OscParser.new.parse @meta_request.ddl_statement
      run_action = Migration.types[:action][result[:action]]
    rescue
      run_action = Migration.types[:run][:action]
    end

    @migrations = @meta_request.migrations

    @available_actions = []
    @editable = true
    @deleteable = @migrations.any? ? false : true
    return unless @migrations.any?

    # the following authorizations are expensive to check, and therefore we only
    # run them on one migration in the meta request. if a user has the authorization
    # to do an action to one migration in a meta request, they SHOULD have the
    # authorization to do that action to all migrations in the meta request
    mig = @migrations.first
    can_do_any_action = policy(mig).any_action?
    can_do_run_action = policy(mig).run_action?
    can_approve = policy(mig).approve?
    is_migration_requestor = current_user_name == mig.requestor

    # get the actions available for each migration
    @migrations.each do |m|
      # use initial runtype so we don't have to recalculate the runtype for each
      # migration here (expensive)
      authorized_actions = m.authorized_actions(m.initial_runtype, run_action, can_do_any_action, can_do_run_action,
                                                is_migration_requestor, can_approve)
      @available_actions << authorized_actions
      m.actions = authorized_actions.map {|a| Migration.actions[a]}

      @editable = false unless m.editable?
    end

    action_order = Migration.actions.keys
    @available_actions.flatten!.uniq!
    @available_actions.sort_by! do |e|
      action_order.index(e)
    end unless @available_actions.empty?
  end

  def bulk_action
    action = params[:bulk_action].to_i
    migrations = params[:migrations]
    error = false

    # start a trxn, and select for update all of our data
    ActiveRecord::Base.transaction do
      meta_request = MetaRequest.lock.find(params[:id])
      begin
        result = OscParser.new.parse meta_request.ddl_statement
        run_action = Migration.types[:action][result[:action]]
      rescue
        run_action = Migration.types[:run][:action]
      end

      migration_maps = []
      # check for inconsistencies between the meta request and the migrations selected, just in case
      migrations.each do |m|
        begin
          # TODO: probably don't actually need to lock these since we use "lock_version"
          # on each migrtaion
          migration = Migration.lock.find(m["id"])
          migration_maps << {:migration => migration, :lock_version => m["lock_version"]}
          error = true if migration.ddl_statement != meta_request.ddl_statement
          error = true if migration.meta_request_id != meta_request.id
          error = true if migration.requestor != meta_request.requestor
        rescue ActiveRecord::RecordNotFound
          error = true
        end
      end
      return render json: {:error => error} if error || !migration_maps.any?

      # authorize against the first cluster being submitted. see above for reasoning
      mig = migration_maps.first[:migration]
      can_do_any_action = policy(mig).any_action?
      can_do_run_action = policy(mig).run_action?
      can_approve = policy(mig).approve?
      # verify that the user is authorized to run the bulk action on the selected migrations
      migration_maps.each do |m|
        is_migration_requestor = current_user_name == m[:migration].requestor
        authorized_actions = m[:migration].authorized_actions(m[:migration].initial_runtype, run_action, can_do_any_action,
                                    can_do_run_action, is_migration_requestor, can_approve)
        unless authorized_actions.any? {|a| Migration.actions[a] == action}
          error = true
        end
      end

      # if there are any inconsistencies, don't even try to apply the action
      return render json: {:error => error} if error

      migration_maps.each do |m|
        resp = case action
        when Migration.actions[:approve_long]
          m[:migration].approve!(current_user_name, Migration.types[:run][:long], m[:lock_version])
        when Migration.actions[:approve_short]
          m[:migration].approve!(current_user_name, Migration.types[:run][:short], m[:lock_version])
        when Migration.actions[:approve_nocheckalter]
          m[:migration].approve!(current_user_name, Migration.types[:run][:nocheckalter], m[:lock_version])
        when Migration.actions[:unapprove]
          m[:migration].unapprove!(m[:lock_version])
        when Migration.actions[:start]
          # bulk action starts don't start migs directly...queue them up instead
          m[:migration].enqueue!(m[:lock_version])
        when Migration.actions[:rename]
          m[:migration].rename!(m[:lock_version])
        when Migration.actions[:pause]
          m[:migration].pause!
        when Migration.actions[:resume]
          m[:migration].resume!(m[:lock_version], auto_run = true)
        when Migration.actions[:cancel]
          m[:migration].cancel!
        when Migration.actions[:delete]
          m[:migration].delete!(m[:lock_version])
        when Migration.actions[:dequeue]
          m[:migration].dequeue!(m[:lock_version])
        end

        # rollback entire transaction and record an error unless each update is successful
        unless resp
          error = true
          # if the action is "cancel", don't roll back and try to continue canceling
          # (for safety reasons)
          raise ActiveRecord::Rollback unless action == Migration.actions[:cancel]
        end
      end
    end

    render json: {:error => error}
  end

  def new
    @saved_state = {
      :ddl_statement => params[:ddl_statement],
      :final_insert  => params[:final_insert],
      :pr_url        => params[:pr_url],
      :cluster_dbs   => (params[:databases] || []).map {|cluster_db| cluster_db.split ':'}
        .inject({}) { |h, cluster_db| (h[cluster_db[0]] ||= []) << cluster_db[1]; h }
    }
    @meta_request = nil
  end

  def create
    ddl_statement = params[:ddl_statement]
    final_insert = params[:final_insert]
    pr_url = params[:pr_url]
    databases = params[:databases]
    clusters = params[:clusters]
    no_errors = []
    errors = []

    # for each cluster/database combo, create a new migration and validate it. if
    # all migrations are valid, create a meta request and then create all the migrations.
    # if any of them don't validate, don't create a meta request and return all errors
    # back to the UI
    if databases
      app_name = ""
      databases.each_with_index do |cluster_db, i|
        parts = cluster_db.split(":")
        next unless parts.length == 2
        cluster_name = parts[0]
        database = parts[1]

        # verify that the app name is the same for all clusters. this is a
        # good idea on its own, but it's also important because we only check
        # authorization for the user based on the app of the first cluster
        current_app_name = Cluster.find_by(:name => cluster_name).app
        if i == 0
          app_name = current_app_name
        else
          if current_app_name != app_name
            errors << OpenStruct.new({
              :cluster_name  => cluster_name,
              :database      => database,
              :errors        => OpenStruct.new({
                :full_messages => ["cluster belongs to a different app than the first cluster"\
                                   " (#{current_app_name} vs #{app_name})"]
              })
            })
            next
          end
        end

        migration = Form::NewMigrationRequest.new({
          "cluster_name"  => cluster_name,
          "database"      => database,
          "ddl_statement" => ddl_statement,
          "pr_url"        => pr_url,
          "requestor"     => current_user_name,
          "final_insert"  => final_insert,
          "runtype"       => Migration.types[:run][:undecided],
        })
        if migration.validate
          no_errors << migration
        else
          errors << migration
        end
      end

      if errors.length <= 0
        mr = MetaRequest.new({
          :ddl_statement => ddl_statement,
          :final_insert  => final_insert,
          :pr_url        => pr_url,
          :requestor     => current_user_name,
        })
        if mr.save
          no_errors.each { |m| m.meta_request_id = mr.id; m.save }
          MetaRequestMailer.new_meta_request(mr).deliver_now
          return redirect_to meta_request_path(mr)
        end
      end
    else
      if clusters
        clusters.each do |c|
          # make a struct that functions just like an ActiveRecord validation error
          errors << OpenStruct.new({
            :cluster_name  => c,
            :database      => nil,
            :errors        => OpenStruct.new({
              :full_messages => ["database can't be blank"]
            })
          })
        end
      else
          errors << OpenStruct.new({
            :cluster_name  => nil,
            :database      => nil,
            :errors        => OpenStruct.new({
              :full_messages => ["cluster can't be blank", "database can't be blank"]
            })
          })
      end
    end

    @errors = errors
    # save the current state so that the form can be auto-populated when we refresh
    @saved_state = {
      :ddl_statement => ddl_statement,
      :final_insert  => final_insert,
      :pr_url        => pr_url,
      :cluster_dbs   => {},
    }
    @errors.each do |error|
      @saved_state[:cluster_dbs][error.cluster_name] ||= []
      @saved_state[:cluster_dbs][error.cluster_name] << error.database if error.database
    end
    no_errors.each do |mig|
      @saved_state[:cluster_dbs][mig.cluster_name] ||= []
      @saved_state[:cluster_dbs][mig.cluster_name] << mig.database
    end
    # display errors
    render action: 'new'
  end

  def edit
    @meta_request = MetaRequest.find(params[:id])
    @saved_state = {
      :ddl_statement => @meta_request.ddl_statement,
      :final_insert  => @meta_request.final_insert,
      :pr_url        => @meta_request.pr_url,
    }
  end

  def update
    @errors = []
    updated = {
      "ddl_statement" => params[:ddl_statement],
      "pr_url"        => params[:pr_url],
      "final_insert"  => params[:final_insert],
      "requestor"     => current_user_name,
    }

    ActiveRecord::Base.transaction do
      @meta_request = MetaRequest.lock.find(params[:id])

      @meta_request.assign_attributes(updated)
      # if we could update the meta request, try to update all the migrations that
      # belong to the meta request. roll everything back if there are any failures
      if @meta_request.save
        @meta_request.migrations.each do |m|
          migration = Form::EditMigrationRequest.new(
            m,
            updated
          )

          if migration.editable?
            # try to save the migration
            unless migration.save
              @errors = [OpenStruct.new({
                :cluster_name  => migration.cluster_name,
                :database      => migration.database,
                :errors        => OpenStruct.new({
                  :full_messages => ["this migration (which is part of the meta request) failed to be
                                      updated, so we rolled everything back."]
                })
              })]

              # roll back the transaction
              raise ActiveRecord::Rollback
            end
          else
            @errors = [OpenStruct.new({
              :cluster_name  => migration.cluster_name,
              :database      => migration.database,
              :errors        => OpenStruct.new({
                :full_messages => ["this migration (which is part of the meta request) can't be edited,
                                    so we rolled everything back. your best bet is to re-file a new meta request."]
              })
            })]

            # roll back the transaction
            raise ActiveRecord::Rollback
          end
        end
        return redirect_to meta_request_path(@meta_request)
      end
    end

    # save the current state so that the form can be auto-populated when we refresh
    @saved_state = {
      :ddl_statement => updated["ddl_statement"],
      :final_insert  => updated["final_insert"],
      :pr_url        => updated["pr_url"],
    }

    # display errors
    render action: 'edit'
  end

  def destroy
    @meta_request = MetaRequest.find(params[:id])
    if @meta_request.migrations.any?
      redirect_to @meta_request
    else
      @meta_request.destroy
      redirect_to root_url
    end
  end
end
