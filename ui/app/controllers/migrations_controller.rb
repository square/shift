class MigrationsController < ApplicationController
  def index
    @migrations = {}
    state = params[:state]
    additional_filters = {}
    like_filters = []
    additional_filters.merge!(:cluster_name => params[:cluster]) if params[:cluster]
    additional_filters.merge!(:requestor => params[:requestor]) if params[:requestor]
    like_filters = ["ddl_statement like (?)", "%#{params[:ddl_statement]}%"] if params[:ddl_statement]

    @cluster_name = params[:cluster]
    @requestor = params[:requestor]
    @ddl_statement = params[:ddl_statement]
    # when we want to see all migrations for a state, we paginate through them
    if state
      @migrations[state] = Migration.migrations_by_state(state, limit: nil, additional_filters: additional_filters,
                                                         like_filters: like_filters, page: params[:page])
      @limit = false
      @counts = Migration.counts_by_state([state], additional_filters: additional_filters, like_filters: like_filters)
      @show_filter = false
    else
      default_states = Migration.default_states
      default_states.each do |dstate|
        @migrations[dstate] = Migration.migrations_by_state(dstate, additional_filters: additional_filters,
                                                            like_filters: like_filters)
      end
      @limit = true
      @counts = Migration.counts_by_state(default_states, additional_filters: additional_filters,
                                          like_filters: like_filters)

      # data for filters
      @show_filter = true
      @cluster_names = Migration.select(:cluster_name).map(&:cluster_name).uniq.sort
      @requestors = Migration.select(:requestor).map(&:requestor).uniq.sort
    end

    @statuses = Statuses.all.index_by(&:status)
  end

  def show
    @migration = Migration.find(params[:id])
    @status = Statuses.find_by_status!(@migration.status)
    profile_client = Profile.new
    comment_authors = Comment.where(:migration_id => params[:id]).pluck(:author)
    comment_authors << current_user_name
    @profile = {}
    comment_authors.uniq.each do |a|
      @profile[a] = {:photo => profile_client.primary_photo(a)}
    end
  end

  def refresh_detail
    @migration = Migration.find(params[:id])
    @status = Statuses.find_by_status!(@migration.status)
    render :json => {:detailPartial => render_to_string('migrations/_detail', :layout => false,
                                                         :locals => { :migration => @migration, :status => @status}),
                     :copy_percentage => @migration.copy_percentage, :status => @migration.status}
  end

  def table_stats
    migration = Migration.find(params[:id])
    begin
      table = OscParser.new.parse(migration.ddl_statement)[:table]
    rescue # skip unpasable statements
    end
    last_alter_date, last_alter_duration, average_alter_duration = get_table_stats(
      migration.cluster_name,
      migration.database,
      table)
    render :json => {
      :last_alter_date => last_alter_date,
      :last_alter_duration => last_alter_duration,
      :average_alter_duration => average_alter_duration
    }
  end

  def status_image
    respond_to do |format|
      format.png do
        @migration = Migration.find(params[:id])
        @status = Statuses.find_by_status!(@migration.status)
        img_html = render_to_string('migrations/_status', :layout => false,
                                    :locals => { :migration => @migration, :status => @status }, :formats => [:html])
        begin
          kit = IMGKit.new(img_html, width: 350)
          send_data(kit.to_png, :type => "image/png", :disposition => 'inline')
        rescue
          return send_file Rails.root.join("public", "imgkit_error.png"), type: "image/png", disposition: "inline"
        end
      end
    end
  end

  def new
    @migration = Form::NewMigrationRequest.new

    # the below params are set when you "clone" a migration
    valid_attributes = [:cluster_name, :database, :ddl_statement, :pr_url, :final_insert, :max_threads_running, :max_replication_lag,
                        :config_path, :recursion_method]
    valid_attributes.each do |attr|
      if params.has_key?(attr.to_s)
        @migration.send("#{attr}=", params[attr.to_s])
      end
    end
  end

  def create
    @migration = Form::NewMigrationRequest.new(params.require(:form_new_migration_request).merge(requestor: current_user_name))
    if @migration.save
      MigrationMailer.new_migration(@migration).deliver_now
      redirect_to migration_path(id: @migration.dao.id)
    else
      render action: 'new'
    end
  end

  def edit
    @migration = Form::EditMigrationRequest.new(Migration.find(params[:id]))
  end

  def update
    @migration = Form::EditMigrationRequest.new(
      Migration.find(params[:id]),
      params.require(:form_edit_migration_request).merge(requestor: current_user_name)
    )

    # lock_version is not so important here...if the migration is editable, it will get
    # updated. even if the lock_version were to change but the mig was still in an
    # editable state, the end user probably wouldn't care if we just edited it
    if @migration.editable? && (params[:form_edit_migration_request][:lock_version].to_i == @migration.dao.lock_version) &&
        !@migration.meta_request_id
      if @migration.save
        redirect_to migration_path(@migration)
      else
        render action: 'edit'
      end
    else
      redirect_to migration_path(@migration)
    end
  end

  def destroy
    @migration = Migration.find(params[:id])
    authorize @migration

    if @migration.delete!(params[:lock_version])
      redirect_to root_url
    else
      redirect_to @migration
    end
  end

  def approve
    @migration = Migration.find(params[:id])
    authorize @migration, :approve?

    # don't let user decide if maybeshort should be a short run unless the table is really
    # small or they can approve dangerous things. also don't let them decide nocheck-alter
    if (params[:runtype].to_i == Migration.types[:run][:short] &&
        (@migration.parsed[:run] == :maybeshort && !@migration.small_enough_for_short_run?))
      authorize @migration, :approve_dangerous?
    end
    if (params[:runtype].to_i == Migration.types[:run][:nocheckalter] && @migration.parsed[:run] == :maybenocheckalter)
      authorize @migration, :approve_dangerous?
    end

    if @migration.approve!(current_user_name, params[:runtype].to_i, params[:lock_version])
      @migration.reload
      send_notifications
    end
    redirect_to @migration
  end

  def unapprove
    @migration = Migration.find(params[:id])
    authorize @migration, :approve?

    if @migration.unapprove!(params[:lock_version])
      @migration.reload
      send_notifications
    end
    redirect_to @migration
  end

  def start
    @migration = Migration.find(params[:id])
    authorize @migration, :run_action?

    if @migration.start!(params[:lock_version])[0]
      @migration.reload
      send_notifications
    end
    redirect_to @migration
  end

  def pause
    @migration = Migration.find(params[:id])
    authorize @migration, :run_action?

    if @migration.pause!
      @migration.reload
      send_notifications
    end
    redirect_to @migration
  end

  def rename
    @migration = Migration.find(params[:id])
    authorize @migration, :run_action?

    if @migration.rename!(params[:lock_version])
      @migration.reload
      send_notifications
    end
    redirect_to @migration
  end

  def resume
    @migration = Migration.find(params[:id])
    authorize @migration, :run_action?

    if @migration.resume!(params[:lock_version])
      @migration.reload
      send_notifications
    end
    redirect_to @migration
  end

  def dequeue
    @migration = Migration.find(params[:id])
    authorize @migration, :run_action?

    @migration.dequeue!(params[:lock_version])
    redirect_to @migration
  end

  def cancel
    @migration = Migration.find(params[:id])
    authorize @migration, :run_action?

    if @migration.cancel!
      @migration.reload
      send_notifications
    end

    redirect_to @migration
  end

  private

  def get_table_stats(cluster_name, database, table)
    return "N/A", "N/A", "N/A" if !cluster_name || !database || !table

    last_alter_date = nil
    last_alter_duration = nil
    average_alter_duration = nil
    times_altered = 0

    Migration.where("cluster_name = ? AND `database` = ? AND started_at IS NOT NULL AND completed_at IS NOT NULL",
      cluster_name, database).order("started_at").each do |migration|
      begin
        migration_table = OscParser.new.parse(migration.ddl_statement)[:table]
      rescue
        next # skip unparsable statements
      end

      next if table != migration_table

      alter_duration = migration.completed_at - migration.started_at

      last_alter_date = migration.started_at.to_s.split[0]
      last_alter_duration = alter_duration
      times_altered += 1
      if average_alter_duration
        average_alter_duration = (average_alter_duration * (times_altered - 1) + alter_duration) / times_altered
      else
        average_alter_duration = alter_duration
      end

    end

    return "N/A", "N/A", "N/A" if times_altered == 0

    return Date.strptime(last_alter_date, ("%Y-%m-%d")).strftime("%m/%d/%Y"),
      last_alter_duration, average_alter_duration
  end

  def send_notifications
    Notifier.notify("migration id #{@migration.id} moved to status #{@migration.status} from the UI by #{current_user_name}")
    MigrationMailer.migration_status_change(@migration).deliver_now
  end

  def show_failure?
    skipped_status = [:completed, :canceled].map { |e| Migration.status_groups[e] }
    return false if skipped_status.include? @migration.status
    @migration.init_parse
    @migration[:error_message]
  end
  helper_method :show_failure?

  def show_delete?
    Migration.status_groups[:deletable].include?(@migration.status) && policy(@migration).destroy?
  end
  helper_method :show_delete?

  def show_cancel?
    Migration.status_groups[:cancelable].include?(@migration.status) && policy(@migration).run_action?
  end
  helper_method :show_cancel?

  def show_approve?
    (Migration.status_groups[:awaiting_approval] == @migration.status) && policy(@migration).approve?
  end
  helper_method :show_approve?

  def show_unapprove?
    (Migration.status_groups[:awaiting_start] == @migration.status) && policy(@migration).approve?
  end
  helper_method :show_unapprove?

  def show_start?
    (Migration.status_groups[:awaiting_start] == @migration.status) && policy(@migration).run_action?
  end
  helper_method :show_start?

  def show_pause?
    # don't show the pause button for short runs
    (Migration.status_groups[:copy_in_progress] == @migration.status) && policy(@migration).run_action? &&
      use_ptosc?
  end
  helper_method :show_pause?

  def show_rename?
    (Migration.status_groups[:awaiting_rename] == @migration.status) && policy(@migration).run_action?
  end
  helper_method :show_rename?

  def show_resume?
    ([Migration.status_groups[:error], Migration.status_groups[:paused]].include?(@migration.status)) &&
      policy(@migration).run_action?
  end
  helper_method :show_resume?

  def show_dequeue?
    (Migration.status_groups[:enqueued] == @migration.status) && policy(@migration).run_action?
  end
  helper_method :show_dequeue?

  def show_edit?
    # migrations that are part of meta requests can't be updated outside
    # of their meta request
    @migration.editable? && !@migration.meta_request_id
  end
  helper_method :show_edit?

  def use_ptosc?
    if @migration.runtype == Migration.types[:run][:undecided]
      @migration.parsed[:run] != :short
    else
      @migration.runtype != Migration.types[:run][:short]
    end
  end
  helper_method :use_ptosc?

  def migration_in_progress?
    Migration.status_groups[:pending].include?(@migration.status) || Migration.status_groups[:running].include?(@migration.status)
  end
  helper_method :migration_in_progress?

  def action_type
    @migration.parsed[:action]
  end
  helper_method :action_type

  # a migration is blocked if it cannot be started due to too many migrations already running
  # for the same cluster
  def is_blocked?
    @migration.cluster_running_maxed_out?
  end
  helper_method :is_blocked?
end
