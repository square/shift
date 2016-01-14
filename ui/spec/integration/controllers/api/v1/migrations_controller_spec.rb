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

  describe 'GET #show' do
    before (:each) do
      @migration = FactoryGirl.create(:migration, cluster_name: @cluster.name)
      get :show, id: @migration
    end

    it 'assings the requested migration to @migration' do
      expect(assigns(:migration)).to eq(@migration)
    end

    it 'returns migration as json' do
      expect(json["id"]).to eq(@migration["id"])
    end

    it 'returns a 200 status code' do
      expect(response).to have_http_status(200)
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
end
