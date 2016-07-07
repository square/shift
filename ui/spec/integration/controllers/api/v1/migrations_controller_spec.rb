require 'integration_helper'
require 'shared_setup'

RSpec.describe Api::V1::MigrationsController, type: :controller do
  include_context "shared setup"

  let(:osc_parser) { instance_double(OscParser) }

  def valid_attributes(extra = {})
    {
      :table_rows_start  => 1000,
      :table_rows_end    => 1200,
      :table_size_start  => 5555,
      :table_size_end    => 6666,
      :index_size_start  => 400,
      :index_size_end    => 500,
      :work_directory    => "/data/tmp/mig1-statefile.txt",
      :copy_percentage   => 100,
      :run_host          => "run.host.name",
    }.merge(extra).with_indifferent_access
  end

  before (:each) do
    @cluster = FactoryGirl.create(:cluster)
  end

  describe 'GET #staged' do
    before (:each) do
      @migration = FactoryGirl.create(:staged_run_migration, cluster_name: @cluster.name)
    end

    context 'less than UNSTAGE_LIMIT number of migrations' do
      it 'populates array of staged migrations' do
        get :staged
        expect(assigns(:migrations)).to eq([@migration])
      end

      it 'returns migrations as json' do
        get :staged
        expect(json.count).to eq(1)
        expect(json[0]["cluster_name"]).to eq(@migration["cluster_name"])
      end

      it 'returns a 200 status code' do
        get :staged
        expect(response).to have_http_status(200)
      end
    end

    context 'more than UNSTAGE_LIMIT number of migrations' do
      before (:each) do
        # create migrations to take it over the unstage_limit
        Migration.unstage_limit.times do
          @migration = FactoryGirl.create(:staged_run_migration, cluster_name: @cluster.name)
        end
        get :staged
      end

      it 'returns migrations as json, but only returns $unstage_limit number of migrations' do
        expect(json.count).to eq(Migration.unstage_limit)
        expect(json[0]["cluster_name"]).to eq(@migration["cluster_name"])
      end

      it 'returns a 200 status code' do
        expect(response).to have_http_status(200)
      end
    end

    context 'host and port get added to the payload' do
      it 'appends a host field with the cluster hostname' do
        get :staged
        expect(json[0]["host"]).to eq(@migration.cluster.rw_host)
      end

      it 'appends a host field with the cluster port' do
        get :staged
        expect(json[0]["port"]).to eq(@migration.cluster.port)
      end

      it 'does not show the migration if the host cannot be retrieved' do
        @cluster.update_attribute(:rw_host, nil)
        get :staged
        expect(json.length).to eq(0)
      end
    end

    context 'runtype, ddl, table, mode, and action get updated in the payload' do
      before (:each) do
        allow(OscParser).to receive(:new).and_return(osc_parser)
        allow(osc_parser).to receive(:merge_checkers!)
      end

      it 'changes undecided runtype to long because that is the safest' do
        allow(osc_parser).to receive(:parse).and_return({run: :maybeshort})
        @migration.runtype = Migration.types[:run][:undecided]
        @migration.reload
        get :staged
        expect(json[0]["runtype"]).to eq(Migration.types[:run][:long])
      end

      it 'changes undecided runtype to short because the parser determined it is forsure short' do
        allow(osc_parser).to receive(:parse).and_return({run: :short})
        @migration.runtype = Migration.types[:run][:undecided]
        @migration.reload
        get :staged
        expect(json[0]["runtype"]).to eq(Migration.types[:run][:short])
      end

      it 'changes the ddl_statement to the parsed version' do
        allow(osc_parser).to receive(:parse).and_return({stm: "parsed ddl"})
        get :staged
        expect(json[0]["ddl_statement"]).to eq("parsed ddl")
      end

      it 'changes the table to the parsed version' do
        allow(osc_parser).to receive(:parse).and_return({table: "parsed_table"})
        get :staged
        expect(json[0]["table"]).to eq("parsed_table")
      end

      it 'changes the mode to the parsed version' do
        allow(osc_parser).to receive(:parse).and_return({mode: :table})
        get :staged
        expect(json[0]["mode"]).to eq(Migration.types[:mode][:table])
      end

      it 'changes the action to the parsed version' do
        allow(osc_parser).to receive(:parse).and_return({action: :alter})
        get :staged
        expect(json[0]["action"]).to eq(Migration.types[:action][:alter])
      end
    end
  end

  describe 'POST #unstage' do
    context 'is staged' do
      before (:each) do
        @migration = FactoryGirl.create(:staged_migration, cluster_name: @cluster.name)
      end

      it 'unstages a staged migration' do
        expect(@migration.staged?).to eq(true)
        post :unstage, id: @migration
        @migration.reload
        expect(@migration.staged?).to eq(false)
      end

      it 'returns migration as json' do
        post :unstage, id: @migration
        @migration.reload
        expect(json["id"]).to eq(@migration["id"])
      end

      it 'returns a 200 status code' do
        post :unstage, id: @migration
        expect(response).to have_http_status(200)
      end
    end
    context 'is not staged' do
      before (:each) do
        @migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
      end

      it 'unstages a migration that is not staged' do
        expect(@migration.staged?).to eq(false)
        post :unstage, id: @migration
        @migration.reload
        expect(@migration.staged?).to eq(false)
      end

      it 'returns empty as json' do
        post :unstage, id: @migration
        @migration.reload
        expect(json).to eq({})
      end

      it 'returns a 200 status code' do
        post :unstage, id: @migration
        expect(response).to have_http_status(200)
      end
    end
  end

  describe 'POST #next_step' do
    context 'can move to next_step' do
      it 'moves the migration to the next step' do
        migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
        starting_status = migration.status
        post :next_step, id: migration
        migration.reload
        expect(migration.status).to eq(starting_status + 1)
      end

      it 'returns migration as json' do
        migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
        post :next_step, id: migration
        migration.reload
        expect(json["id"]).to eq(migration["id"])
      end

      it 'returns a 200 status code' do
        migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
        post :next_step, id: migration
        migration.reload
        expect(response).to have_http_status(200)
      end
    end

    context 'cannot move to next_step' do
      before :each do
        @migration = FactoryGirl.create(:human_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :next_step, id: @migration
        @migration.reload
      end

      it 'does not move the migration to the next step' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'returns migration as json' do
        expect(json["id"]).to eq(@migration["id"])
      end

      it 'returns a 200 status code' do
        expect(response).to have_http_status(200)
      end
    end
  end

  describe 'PATCH #update' do
    context 'with valid attributes' do
      before (:each) do
        @migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
        patch :update, {id: @migration}.merge(valid_attributes)
        @migration.reload
      end

      it 'updates a migration' do
        valid_attributes.each do |attribute, value|
          expect(@migration[attribute]).to eq(value)
        end
      end

      it 'returns migration as json' do
        expect(json["id"]).to eq(@migration["id"])
      end

      it 'returns a 200 status code' do
        expect(response).to have_http_status(200)
      end
    end

    context 'with invalid attributes' do
      before (:each) do
        @migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
        @original_cluster_name = @migration.cluster_name
        patch :update, {id: @migration}.merge({:cluster_name => "badcluster"})
        @migration.reload
      end

      it 'does not update a migration' do
        expect(@migration.cluster_name).to eq(@original_cluster_name)
      end

      it 'returns migration as json' do
        expect(json["id"]).to eq(@migration["id"])
      end

      it 'returns a 200 status code' do
        expect(response).to have_http_status(200)
      end
    end
  end

  describe 'POST #complete' do
    it 'completes the migration' do
      migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
      post :complete, id: migration
      migration.reload
      expect(migration.status).to eq(Migration.status_groups["completed"])
    end

    it 'returns migration as json' do
      migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
      post :complete, id: migration
      migration.reload
      expect(json["id"]).to eq(migration["id"])
    end

    it 'sets completed_at' do
      migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
      expect(migration.completed_at).to eq(nil)
      post :complete, id: migration
      migration.reload
      expect(migration.completed_at.utc).to be_within(2).of Time.now
    end

    it 'returns a 200 status code' do
      migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
      post :complete, id: migration
      migration.reload
      expect(response).to have_http_status(200)
    end
  end

  describe 'POST #cancel' do
    it 'cancelss the migration' do
      migration = FactoryGirl.create(:cancelable_migration, cluster_name: @cluster.name)
      post :cancel, id: migration
      migration.reload
      expect(migration.status).to eq(Migration.status_groups["canceled"])
    end

    it 'returns migration as json' do
      migration = FactoryGirl.create(:cancelable_migration, cluster_name: @cluster.name)
      post :cancel, id: migration
      migration.reload
      expect(json["id"]).to eq(migration["id"])
    end

    it 'stages the migration' do
      migration = FactoryGirl.create(:running_migration, cluster_name: @cluster.name)
      post :cancel, id: migration
      migration.reload
      expect(migration.staged).to eq(true)
    end

    it 'returns a 200 status code' do
      migration = FactoryGirl.create(:cancelable_migration, cluster_name: @cluster.name)
      post :cancel, id: migration
      migration.reload
      expect(response).to have_http_status(200)
    end
  end

  describe 'POST #fail' do
    before (:each) do
      @migration = FactoryGirl.create(:machine_migration, cluster_name: @cluster.name)
      post :fail, {id: @migration}.merge({:error_message => "Error message."})
      @migration.reload
    end

    it 'fails a migration' do
      expect(@migration[:error_message]).to eq("Error message.")
    end

    it 'returns migration as json' do
      expect(json["id"]).to eq(@migration["id"])
    end

    it 'returns a 200 status code' do
      expect(response).to have_http_status(200)
    end
  end

  describe 'POST #error' do
    before (:each) do
      @migration = FactoryGirl.create(:copy_migration, cluster_name: @cluster.name)
      post :error, {id: @migration}.merge({:error_message => "Error message."})
      @migration.reload
    end

    it 'errors a migration' do
      expect(@migration[:error_message]).to eq("Error message.")
    end

    it 'returns migration as json' do
      expect(json["id"]).to eq(@migration["id"])
    end

    it 'returns a 200 status code' do
      expect(response).to have_http_status(200)
    end
  end

  describe 'POST #offer' do
    before (:each) do
      @migration = FactoryGirl.create(:copy_migration, cluster_name: @cluster.name)
      post :offer, id: @migration.id
      @migration.reload
    end

    it 'puts migration in staged and copy_in_progress' do
      expect(@migration[:staged]).to eq(true)
      expect(@migration[:status]).to eq(Migration.status_groups[:copy_in_progress])
    end

    it 'returns migration as json' do
      expect(json["id"]).to eq(@migration["id"])
    end

    it 'returns a 200 status code' do
      expect(response).to have_http_status(200)
    end
  end

  describe 'POST #unpin_run_host' do
    before (:each) do
      @migration = FactoryGirl.create(:migration, run_host: "host")
      post :unpin_run_host, id: @migration.id
      @migration.reload
    end

    it 'puts makes the migrations\'s run_host nil' do
      expect(@migration[:run_host]).to be_nil
    end

    it 'returns migration as json' do
      expect(json["id"]).to eq(@migration["id"])
    end

    it 'returns a 200 status code' do
      expect(response).to have_http_status(200)
    end
  end

  describe 'POST #append_to_file' do
    before (:each) do
      @log_type = ShiftFile.file_types[:log]
    end

    it 'creates a new file if file not found' do
      post :append_to_file, migration_id: 123, file_type: @log_type, contents: "test content"
      expect(response).to have_http_status(200)
      expect(json["migration_id"]).to eq(123)
      expect(json["file_type"]).to eq(@log_type)
      expect(json["contents"]).to eq("Content omitted...")
      expect(ShiftFile.find_by(migration_id: 123, file_type: @log_type).contents).to eq("test content")
    end

    it 'appends to contents if file already exists' do
      @shift_file = FactoryGirl.create(:shift_file, migration_id: 123, file_type: @log_type, contents: "test content")
      post :append_to_file, migration_id: 123, file_type: @log_type, contents: "test content"
      expect(response).to have_http_status(200)
      expect(json["id"]).to eq(@shift_file.id)
      expect(json["migration_id"]).to eq(123)
      expect(json["file_type"]).to eq(@log_type)
      expect(json["contents"]).to eq("Content omitted...")
      expect(ShiftFile.find_by(migration_id: 123, file_type: @log_type).contents).to eq("test contenttest content")
    end

    it 'errors when file type is not appendable' do
      post :append_to_file, migration_id: 123, file_type: ShiftFile.file_types[:state], contents: "test content"
      expect(response).to have_http_status(400)
    end
  end

  describe 'POST #write_file' do
    before (:each) do
      @state_type = ShiftFile.file_types[:state]
    end

    it 'creates a new file if file not found' do
      post :write_file, migration_id: 123, file_type: @state_type, contents: "test content"
      expect(response).to have_http_status(200)
      expect(json["migration_id"]).to eq(123)
      expect(json["file_type"]).to eq(@state_type)
      expect(json["contents"]).to eq("Content omitted...")
      expect(ShiftFile.find_by(migration_id: 123, file_type: @state_type).contents).to eq("test content")
    end

    it 'overwrites contents if file already exists' do
      @shift_file = FactoryGirl.create(:shift_file, migration_id: 123, file_type: @state_type, contents: "test content")
      post :write_file, migration_id: 123, file_type: @state_type, contents: "hi i am a content"
      expect(response).to have_http_status(200)
      expect(json["id"]).to eq(@shift_file.id)
      expect(json["migration_id"]).to eq(123)
      expect(json["file_type"]).to eq(@state_type)
      expect(json["contents"]).to eq("Content omitted...")
      expect(ShiftFile.find_by(migration_id: 123, file_type: @state_type).contents).to eq("hi i am a content")
    end

    it 'errors when file type is not writable' do
      post :write_file, migration_id: 123, file_type: ShiftFile.file_types[:log], contents: "test content"
      expect(response).to have_http_status(400)
    end
  end

  describe 'GET #get_file' do
    before (:each) do
      FactoryGirl.create(:shift_file, migration_id: 123, file_type: 1, contents: "test content")
    end

    it 'returns file as json' do
      get :get_file, migration_id: 123, file_type: 1
      expect(json["migration_id"]).to eq(123)
      expect(json["file_type"]).to eq(1)
      expect(json["contents"]).to eq("test content")
    end

    it 'returns a 200 status code' do
      get :get_file, migration_id: 123, file_type: 1
      expect(response).to have_http_status(200)
    end

    it 'returns a 404 status code when file cannot be found' do
      get :get_file, migration_id: 999, file_type: 1
      expect(response).to have_http_status(404)
    end
  end

  describe 'GET #show' do
    before (:each) do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, status: 1,
                                      ddl_statement: "alter table b add column c int")
      get :show, id: @migration
    end

    it 'returns migration as json' do
      expect(json["migration"]["id"]).to eq(@migration["id"])
    end

    it 'returns available actions as json' do
      expect(json["available_actions"]).to eq(["delete"])
    end

    it 'returns a 200 status code' do
      expect(response).to have_http_status(200)
    end
  end

  describe 'POST #create' do
    context 'with valid attributes' do
      it 'creates a new migration' do
        expect{
          post :create, cluster_name: @cluster.name, database: "db1", ddl_statement: "alter table users add column c int",
               pr_url: "github.com/pr", requestor: "mfinch", final_insert: nil
        }.to change(Migration, :count).by(1)
      end

      it 'returns migration as json' do
        allow_any_instance_of(Migration).to receive(:parsed).and_return({:run => :maybeshort})
        post :create, cluster_name: @cluster.name, database: "db1", ddl_statement: "alter table users add column c int",
             pr_url: "github.com/pr", requestor: "mfinch", final_insert: nil
        expect(json["migration"]["database"]).to eq("db1")
      end

      it 'returns a 200 status code' do
        post :create, cluster_name: @cluster.name, database: "db1", ddl_statement: "alter table users add column c int",
             pr_url: "github.com/pr", requestor: "mfinch", final_insert: nil
        expect(response).to have_http_status(200)
      end
    end

    context 'with invalid attributes' do
      it 'does not save a new migration' do
        expect{
          post :create, cluster_name: nil, database: "db1", ddl_statement: "alter table users add column c int",
               pr_url: "github.com/pr", requestor: "mfinch", final_insert: nil
          }.to_not change(Migration, :count)
      end

      it 'returns an error message as json' do
        post :create, cluster_name: nil, database: "db1", ddl_statement: "alter table users add column c int",
             pr_url: "github.com/pr", requestor: "mfinch", final_insert: nil
        expect(json["errors"]).to eq(["Cluster name can't be blank.", "Cluster name is not included in the list.",
                                      "DDL statement is invalid (error: table does not exist!)."])
      end

      it 'returns a 400 status code' do
        post :create, cluster_name: nil, database: "db1", ddl_statement: "alter table users add column c int",
             pr_url: "github.com/pr", requestor: "mfinch", final_insert: nil
        expect(response).to have_http_status(400)
      end
    end
  end

  describe 'POST #approve' do
    context 'migration exists' do
      before (:each) do
        @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                        status: Migration.status_groups["awaiting_approval"],
                                        ddl_statement: "alter table b add column c int", lock_version: 3)
        post :approve, id: @migration, approver: "mfinch", runtype: "long", lock_version: 3
      end

      it 'returns migration as json' do
        expect(json["migration"]["id"]).to eq(@migration["id"])
      end

      it 'returns available actions as json' do
        expect(json["available_actions"]).to eq(["unapprove", "start", "delete", "enqueue"])
      end

      it 'returns a 200 status code' do
        expect(response).to have_http_status(200)
      end
    end

    context 'migration does not' do
      before (:each) do
        post :approve, id: 1234, approver: "mfinch", runtype: "long", lock_version: 3
      end

      it 'returns an error message as json' do
        expect(json["errors"]).to eq(["Migration not found."])
      end

      it 'returns a 404 status code' do
        expect(response).to have_http_status(404)
      end
    end

    context 'invalid action' do
      before (:each) do
        @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                        status: Migration.status_groups["awaiting_start"],
                                        ddl_statement: "alter table b add column c int", lock_version: 3)
        post :approve, id: @migration, approver: "mfinch", runtype: "long", lock_version: 3
      end

      it 'returns an error message as json' do
        expect(json["errors"]).to eq(["Invalid action."])
      end

      it 'returns a 400 status code' do
        expect(response).to have_http_status(400)
      end
    end
  end

  # the following actions are almost identical to #approve, so test less
  describe 'POST #unapprove' do
    it 'returns valid json' do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                      status: Migration.status_groups["awaiting_start"],
                                      ddl_statement: "alter table b add column c int", lock_version: 3)
      post :unapprove, id: @migration, approver: "mfinch", runtype: "long", lock_version: 3
      expect(json["available_actions"]).to eq(["approve_long", "delete"])
      expect(json["migration"]["status"]).to eq(Migration.status_groups["awaiting_approval"])
    end
  end

  describe 'POST #start' do
    it 'returns valid json' do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                      status: Migration.status_groups["awaiting_start"],
                                      ddl_statement: "alter table b add column c int", lock_version: 3)
      post :start, id: @migration, lock_version: 3
      expect(json["available_actions"]).to eq(["pause", "cancel"])
      expect(json["migration"]["status"]).to eq(Migration.status_groups["copy_in_progress"])
      expect(json["migration"]["auto_run"]).to eq(nil)
    end
  end

  describe 'POST #enqueue' do
    it 'returns valid json' do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                      status: Migration.status_groups["awaiting_start"],
                                      ddl_statement: "alter table b add column c int", lock_version: 3)
      post :enqueue, id: @migration, lock_version: 3
      expect(json["available_actions"]).to eq(["dequeue", "delete"])
      expect(json["migration"]["status"]).to eq(Migration.status_groups["enqueued"])
    end
  end

  describe 'POST #dequeue' do
    it 'returns valid json' do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                      status: Migration.status_groups["enqueued"],
                                      ddl_statement: "alter table b add column c int", lock_version: 3)
      post :dequeue, id: @migration, lock_version: 3
      expect(json["available_actions"]).to eq(["unapprove", "start", "delete", "enqueue"])
      expect(json["migration"]["status"]).to eq(Migration.status_groups["awaiting_start"])
    end
  end

  describe 'POST #pause' do
    it 'returns valid json' do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                      status: Migration.status_groups["copy_in_progress"],
                                      ddl_statement: "alter table b add column c int", lock_version: 3)
      post :pause, id: @migration
      expect(json["available_actions"]).to eq(["cancel"])
      expect(json["migration"]["status"]).to eq(Migration.status_groups["pausing"])
    end
  end

  describe 'POST #rename' do
    it 'returns valid json' do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                      status: Migration.status_groups["awaiting_rename"],
                                      ddl_statement: "alter table b add column c int", lock_version: 3)
      post :rename, id: @migration, lock_version: 3
      expect(json["available_actions"]).to eq(["cancel"])
      expect(json["migration"]["status"]).to eq(Migration.status_groups["rename_in_progress"])
    end
  end

  describe 'POST #resume' do
    it 'returns valid json' do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                      status: Migration.status_groups["paused"],
                                      ddl_statement: "alter table b add column c int", lock_version: 3)
      post :resume, id: @migration, lock_version: 3, auto_run: true
      expect(json["available_actions"]).to eq(["pause", "cancel"])
      expect(json["migration"]["status"]).to eq(Migration.status_groups["copy_in_progress"])
      expect(json["migration"]["auto_run"]).to eq(true)
    end
  end

  describe 'POST #cancel_cli' do
    it 'returns valid json' do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                      status: Migration.status_groups["copy_in_progress"],
                                      ddl_statement: "alter table b add column c int", lock_version: 3)
      post :cancel_cli, id: @migration
      expect(json["available_actions"]).to eq([])
      expect(json["migration"]["status"]).to eq(Migration.status_groups["canceled"])
    end
  end

  describe 'DELETE #destroy' do
    context 'migration exists' do
      before (:each) do
        @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                        status: Migration.status_groups["awaiting_approval"],
                                        ddl_statement: "alter table b add column c int", lock_version: 3)
        delete :destroy, id: @migration, lock_version: 3
      end

      it 'returns empty json' do
        expect(json).to eq({})
      end

      it 'returns a 200 status code' do
        expect(response).to have_http_status(200)
      end
    end

    context 'migration does not' do
      before (:each) do
        delete :destroy, id: 1234, lock_version: 3
      end

      it 'returns an error message as json' do
        expect(json["errors"]).to eq(["Migration not found."])
      end

      it 'returns a 404 status code' do
        expect(response).to have_http_status(404)
      end
    end

    context 'invalid action' do
      before (:each) do
        @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name, initial_runtype: 1,
                                        status: Migration.status_groups["completed"],
                                        ddl_statement: "alter table b add column c int", lock_version: 3)
        delete :destroy, id: @migration, lock_version: 3
      end

      it 'returns an error message as json' do
        expect(json["errors"]).to eq(["Invalid action."])
      end

      it 'returns a 400 status code' do
        expect(response).to have_http_status(400)
      end
    end
  end
end
