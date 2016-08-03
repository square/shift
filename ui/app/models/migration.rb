class Migration < ActiveRecord::Base
  has_many :comments
  belongs_to :meta_requests
  paginates_per 20
  before_save :encodeCustomOptions
  after_initialize :decodeCustomOptions
  attr_accessor :actions, :max_threads_running, :max_replication_lag, :config_path, :recursion_method

  belongs_to :cluster, foreign_key: "cluster_name", primary_key: "name"

  STATUS_GROUPS = {
    :all                => [0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14],
    :human              => [1, 2, 4, 6, 12, 13],
    :machine            => [0, 3, 5, 9, 11],
    :end                => [8, 9],
    :pending            => [0, 1, 2, 14],
    :running            => [3, 4, 5, 6, 11, 12, 13],
    :preparing          => 0,
    :awaiting_approval  => 1,
    :awaiting_start     => 2,
    :copy_in_progress   => 3,
    :awaiting_rename    => 4,
    :rename_in_progress => 5,
    :completed          => 8,
    :canceled           => 9,
    :failed             => 10,
    :pausing            => 11,
    :paused             => 12,
    :error              => 13,
    :enqueued           => 14,
    :resumable          => [12, 13],
    :startable          => [2, 14],
    :deletable          => [0, 1, 2, 14],
    :cancelable         => [3, 4, 5, 6, 11, 12, 13],
  }.with_indifferent_access

  ACTIONS = {
    :approve_long         => 0,
    :approve_short        => 1,
    :approve_nocheckalter => 2,
    :unapprove            => 3,
    :start                => 4,
    :rename               => 5,
    :pause                => 6,
    :resume               => 7,
    :cancel               => 8,
    :delete               => 9,
    :dequeue              => 10,
  }

  DEFAULT_STATES = ['pending', 'running', 'completed', 'canceled', 'failed']
  TYPES = {
    run: {undecided: 0, long: 1, short: 2, maybeshort: 3, nocheckalter: 4, maybenocheckalter: 5},
    mode: {table: 0, view: 1},
    action: {create: 0, drop: 1, alter: 2},
  }

  # never let more than N alters run on a cluster at the same time. this prevents load
  # issues from triggers
  PARALLEL_RUN_LIMIT = 1
  # never show more than N unstaged migrations at a time. this prevents the consumer
  # agent from running the prepare step for a ton of migrations at the same time (if
  # 30 are bulk uploaded at once, for example).
  UNSTAGE_LIMIT = 2
  # allow short runs on tables with fewer than this many rows
  SMALL_TABLE_ROW_LIMIT = 5000

  def manage_error(err, include_error)
    @parsed = {
      stm: '',
      run: :undecided,
      table: '',
      lock_version: self.lock_version,
      error: true,
    }
    self.error_message ||= err.message if include_error
  end

  def init_parse(include_error: true)
    return if @parsed && self.lock_version == @parsed[:lock_version]

    begin
      mysql = MysqlHelper.new self.cluster_name
    rescue => e
      manage_error(e, include_error); return
    end

    parser = OscParser.new
    checkers = {
      table_exists: lambda do |mode, table|
        mysql.table_exists? mode, self.database, table
      end,
      get_columns: lambda do |table|
        mysql.columns self.database, table
      end,
      has_referenced_foreign_keys: lambda do |table|
        mysql.has_referenced_foreign_keys? self.database, table
      end,
      get_foreign_keys: lambda do |table|
        mysql.foreign_keys self.database, table
      end,
      avoid_temporal_upgrade?: lambda do
        mysql.avoid_temporal_upgrade?
      end
    }
    parser.merge_checkers! checkers

    begin
      @parsed = parser.parse self.ddl_statement
    rescue => e
      manage_error(e, include_error); return
    end
    @parsed[:lock_version] = self.lock_version
  end

  def parsed
    init_parse; @parsed
  end

  def self.types
    TYPES
  end

  def self.actions
    ACTIONS
  end

  def self.status_groups
    STATUS_GROUPS
  end

  def self.default_states
    DEFAULT_STATES
  end

  def self.parallel_run_limit
    PARALLEL_RUN_LIMIT
  end

  def self.unstage_limit
    UNSTAGE_LIMIT
  end

  def self.small_table_row_limit
    SMALL_TABLE_ROW_LIMIT
  end

  def self.migrations_by_state(state, order: 'updated_at', limit: 5, additional_filters: {},
                               like_filters: [], exclude: {}, page: nil)
    filters = {:status => STATUS_GROUPS[state]}
    filters.merge!(additional_filters)
    return Migration.where(filters).where(like_filters).where.not(exclude).order("#{order} DESC").limit(limit) if limit
    Migration.where(filters).where(like_filters).where.not(exclude).order("#{order} DESC").page(page)
  end

  def self.counts_by_state(states, additional_filters: {}, like_filters: [])
    counts = {}
    states.each do |state|
      filters = {:status => STATUS_GROUPS[state]}
      filters.merge!(additional_filters)
      counts[state] = Migration.where(filters).where(like_filters).count
    end
    counts
  end

  def pending?
    STATUS_GROUPS[:pending].include? self.status
  end

  def editable?
    self.editable
  end

  # can a given migration run on a cluster, or is the cluster already running too
  # many migrations? creates/drops can always run, and alters can run if there aren't
  # more than N already running
  def cluster_running_maxed_out?
    # only alters are affected by too many migrations running on a cluster at once
    return false if (self.parsed[:action] == :create || self.parsed[:action] == :drop)

    # get a list of all the running alters on a cluster
    running_cluster_migs = Migration.where(:cluster_name => self.cluster_name, :status => STATUS_GROUPS[:running])
    filtered = running_cluster_migs.reject do |mig|
      (mig.parsed[:action] == :drop) || (mig.parsed[:action] == :create)
    end
    filtered.length >= PARALLEL_RUN_LIMIT
  end

  def approve!(current_user_name, runtype, lock_version)
    if runtype.is_a? String
      runtype = TYPES[:run][runtype.to_sym]
    end

    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:awaiting_approval], :lock_version => lock_version).
      update_all(:runtype => runtype, :approved_by => current_user_name,
                 :approved_at =>  DateTime.now, :status => STATUS_GROUPS[:awaiting_start])
    updated == 1
  end

  def unapprove!(lock_version)
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:awaiting_start], :lock_version => lock_version).
      update_all(:runtype => TYPES[:run][:undecided], :approved_by => nil,
                 :approved_at =>  nil, :status => STATUS_GROUPS[:awaiting_approval])
    updated == 1
  end

  def start!(lock_version, auto_run = false)
    # only allow a certain number of alters to run per cluster in parallel
    # TODO: make this thread safe
    return false if cluster_running_maxed_out?

    # once a migration has been started, it can never be edited
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:startable], :lock_version => lock_version).
      update_all(:started_at => DateTime.now, :editable => false, :status => STATUS_GROUPS[:copy_in_progress],
                 :staged => true, :auto_run => auto_run)
    updated == 1
  end

  def enqueue!(lock_version)
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:awaiting_start], :lock_version => lock_version).
      update_all(:status => STATUS_GROUPS[:enqueued], :auto_run => true)
    updated == 1
  end

  def dequeue!(lock_version)
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:enqueued], :lock_version => lock_version).
      update_all(:status => STATUS_GROUPS[:awaiting_start], :auto_run => false)
    updated == 1
  end

  def pause!
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:copy_in_progress]).
      update_all(:status => STATUS_GROUPS[:pausing], :staged => true, :auto_run => false)
    updated == 1
  end

  def rename!(lock_version)
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:awaiting_rename], :lock_version => lock_version).
      update_all(:status => STATUS_GROUPS[:rename_in_progress], :staged => true)
    updated == 1
  end

  def resume!(lock_version, auto_run = false)
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:resumable], :lock_version => lock_version).
      update_all(:status => STATUS_GROUPS[:copy_in_progress], :staged => true, :error_message => nil,
                 :auto_run => auto_run)
    updated == 1
  end

  # TODO: consider splitting this out into cancelling/canceled
  def cancel!
    # when a migration is canceled, regardless of the step it's on, we stage
    # it. once the runner unstages it, we don't hear from this migration again
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:cancelable]).
      update_all(:status => STATUS_GROUPS[:canceled], :staged => true)
    updated == 1
  end

  def complete!
    updated = Migration.where(:id => self.id).
      update_all(:status => STATUS_GROUPS[:completed], :completed_at => DateTime.now)
    updated == 1
  end

  def fail!(error_message)
    updated = Migration.where(:id => self.id).
      update_all(:status => STATUS_GROUPS[:failed], :error_message => error_message, :auto_run => false)
    updated == 1
  end

  def error!(error_message)
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:copy_in_progress]).
      update_all(:status => STATUS_GROUPS[:error], :error_message => error_message, :auto_run => false)
    updated == 1
  end

  def delete!(lock_version)
    deleted = Migration.where(:id => self.id, :status => STATUS_GROUPS[:deletable], :lock_version => lock_version).
      destroy_all
    deleted.length == 1
  end

  def offer!
    updated = Migration.where(:id => self.id, :status => STATUS_GROUPS[:copy_in_progress]).
      update_all(:status => STATUS_GROUPS[:copy_in_progress], :staged => true)
    updated == 1
  end

  def unpin_run_host!
    updated = Migration.where(:id => self.id).
      update_all(:run_host => nil)
    updated == 1
  end

  def unstage!
    if self.staged?
      self.staged = false
      return self.save
    end
    false
  end

  def increment_status!
    Migration.increment_counter(:status, self)
    self.save
  end

  def next_step_machine!
    if (STATUS_GROUPS[:machine].include? self.status) && (!self.staged?)
      # bump the status to the next step
      return self.increment_status!
    end
    false
  end

  def app
    cluster.app
  end

  # the main goal of this is to get around the fact that pt-osc won't run on a table that
  # has fewer rows than the chunk size on master, but more rows than the chunk size on at
  # least one of its slaves (if it did run, you'd potentially lose rows on the slave). the
  # default chunk size is 4000, but it doesn't hurt to go a little above that (5000 in this
  # case). the reason we don't support this for migrations that belong to meta requests is
  # because doing so without creating a bad user experience is pretty complicated.
  # specifically, meta requests can't currently handle doing different types of approvals
  # in bulk.
  def small_enough_for_short_run?
    !self.table_rows_start.nil? && self.table_rows_start <= SMALL_TABLE_ROW_LIMIT && self.meta_request_id.nil?
  end

  # this function returns a list of actions that are available to run on a specific
  # migration, taking into account the migrations status, run type, and the authorization
  # of the user. we want to have authorization pre-calculated b/c it can be expensive
  # to determine (this is especially problematic when we loop through many migrations
  # in a meta request)
  def authorized_actions(run_type, run_action, can_do_any_action = false, can_do_run_action = false,
                        is_migration_requestor = false, can_approve = false)
    case self.status
    when Migration.status_groups[:preparing]
      if (can_do_any_action || can_do_run_action || is_migration_requestor)
        [:delete]
      else
        []
      end
    when Migration.status_groups[:awaiting_approval]
      if can_do_any_action
        case run_type
        when Migration.types[:run][:long]
          [(self.small_enough_for_short_run? ? :approve_short : :approve_long), :delete]
        when Migration.types[:run][:short]
          [:approve_short, :delete]
        when Migration.types[:run][:maybeshort]
          [(:approve_long unless self.small_enough_for_short_run?), :approve_short, :delete].compact
        when Migration.types[:run][:maybenocheckalter]
          [(self.small_enough_for_short_run? ? :approve_short : :approve_nocheckalter), :delete]
        else
          [:delete]
        end
      elsif can_approve
        case run_type
        when Migration.types[:run][:long]
          [(self.small_enough_for_short_run? ? :approve_short : :approve_long), :delete]
        when Migration.types[:run][:short]
          [:approve_short, :delete]
        when Migration.types[:run][:maybeshort]
          [(self.small_enough_for_short_run? ? :approve_short : :approve_long), :delete]
        when Migration.types[:run][:maybenocheckalter]
          [(:approve_short if self.small_enough_for_short_run?), :delete].compact
        else
          [:delete]
        end
      elsif (can_do_run_action || is_migration_requestor)
        [:delete]
      else
        []
      end
    when Migration.status_groups[:awaiting_start]
      if can_approve
        [:unapprove, :start , :delete]
      elsif can_do_run_action
        [:start, :delete]
      elsif is_migration_requestor
        [:delete]
      else
        []
      end
    when Migration.status_groups[:copy_in_progress]
      if (can_do_any_action || can_do_run_action)
        case run_action
        when Migration.types[:action][:alter]
          [:pause, :cancel]
        else
          [:cancel]
        end
      else
        []
      end
    when Migration.status_groups[:awaiting_rename]
      if (can_do_any_action || can_do_run_action)
        [:rename, :cancel]
      else
        []
      end
    when Migration.status_groups[:rename_in_progress]
      if (can_do_any_action || can_do_run_action)
        [:cancel]
      else
        []
      end
    when Migration.status_groups[:completed], Migration.status_groups[:failed],
      Migration.status_groups[:canceled]
      []
    when Migration.status_groups[:pausing]
      if (can_do_any_action || can_do_run_action)
        [:cancel]
      else
        []
      end
    when Migration.status_groups[:paused], Migration.status_groups[:error]
      if (can_do_any_action || can_do_run_action)
        [:resume, :cancel]
      else
        []
      end
    when Migration.status_groups[:enqueued]
      if (can_do_any_action || can_do_run_action)
        [:dequeue, :delete]
      else
        []
      end
    else
      []
    end
  end

  private

  def encodeCustomOptions
    self.custom_options = ActiveSupport::JSON.encode(max_threads_running: self.max_threads_running,
                                                     max_replication_lag: self.max_replication_lag,
                                                     config_path: self.config_path,
                                                     recursion_method: self.recursion_method)
  end

  def decodeCustomOptions
    if !self.has_attribute?(:custom_options)
      # prevents MissingAttributeError when doing selects
      return
    end

    if self.custom_options != nil
      decodedOptions = ActiveSupport::JSON.decode(self.custom_options)
      self.max_threads_running = decodedOptions["max_threads_running"]
      self.max_replication_lag = decodedOptions["max_replication_lag"]
      self.config_path = decodedOptions["config_path"]
      self.recursion_method = decodedOptions["recursion_method"]
    end
  end
end
