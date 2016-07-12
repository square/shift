require 'integration_helper'
require 'shared_setup'

RSpec.describe MetaRequestsController, type: :controller do
  include_context "shared setup"

  let(:statuses) { Migration.status_groups }
  let(:profile) { {"developer" => {:photo => "pic.img"}} }

  before(:each) do
    @cluster = FactoryGirl.create(:cluster)
    FactoryGirl.create(:owner, cluster_name: @cluster.name, username: "user1")
    login
  end

  def valid_attributes(extra = {})
    {
      :clusters      => ["appname-001"],
      :databases     => ["appname-001:test", "appname-001:db1"],
      :ddl_statement => 'ALTER TABLE users DROP COLUMN `c`',
      :pr_url        => 'github.com/pr',
      :final_insert  => 'INSERT INTO schema_migrations',
      :max_threads_running => "123",
      :max_replication_lag => "5",
    }.merge(extra).with_indifferent_access
  end

  describe 'GET #index' do
    it 'renders the :index view' do
      get :index
      expect(response).to render_template(:index)
    end

    it 'populates array of meta requests' do
      meta_request = FactoryGirl.create(:meta_request_with_migrations)
      get :index
      expect(assigns(:meta_requests)).to eq([meta_request])
    end

    it 'sets count to be the number of all meta requests' do
      FactoryGirl.create(:meta_request_with_migrations)
      get :index
      expect(assigns(:count)).to eq(1)
    end
  end

  describe 'GET #show' do
    before (:each) do
      @meta_request = FactoryGirl.create(:meta_request_with_migrations)
      get :show, id: @meta_request
    end

    it 'renders the :show view' do
      expect(response).to render_template(:show)
    end

    it 'populates a hash of migration statuses' do
      get :index
      expect(assigns(:statuses)).to eq(Statuses.all())
    end

    it 'assigns the requested meta_request to @meta_request' do
      expect(response).to render_template(:show)
      expect(assigns(:meta_request)).to eq(@meta_request)
    end

    it 'assigns the requested meta_requests migrations to @migrations' do
      expect(response).to render_template(:show)
      expect(assigns(:migrations)).to eq(@meta_request.migrations)
    end

    it 'populates an array of actions that can be run on the migrations' do
      expect(response).to render_template(:show)
      expect(assigns(:available_actions)).to eq([:delete])
    end

    it 'returns an empty array of actions if there are no migs in the meta request' do
      @meta_request = FactoryGirl.create(:meta_request_without_migrations)
      get :show, id: @meta_request
      expect(response).to render_template(:show)
      expect(assigns(:available_actions)).to eq([])
    end

    it 'assigns whether or not the meta request is editable to @editable (true)' do
      expect(response).to render_template(:show)
      expect(assigns(:editable)).to eq(true)
    end

    it 'assigns whether or not the meta request is deleteable to @deleteable (false)' do
      expect(response).to render_template(:show)
      expect(assigns(:deleteable)).to eq(false)
    end

    it 'assigns whether or not the meta request is editable to @editable (false)' do
      FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, editable: false, cluster_name: @cluster.name)
      get :show, id: @meta_request
      expect(response).to render_template(:show)
      expect(assigns(:editable)).to eq(false)
    end
  end

  describe 'GET #new' do
    it 'renders the :new view' do
      get :new
      expect(response).to render_template :new
    end

    context 'with url params' do
      it 'populates a saved_state hash' do
        get :new, {
          :ddl_statement => "alter table", :final_insert => "insert into",
          :pr_url => "github.com", :databases => ["cluster-001:db1", "cluster-001:db2"],
          :max_threads_running => "123", :max_replication_lag => "5", :config_path => "/path/to/file",
          :recursion_method => "some string",
        }
        expect(assigns(:saved_state)).to eq({
          :ddl_statement       => "alter table",
          :final_insert        => "insert into",
          :pr_url              => "github.com",
          :cluster_dbs         => {
            "cluster-001"      => ["db1", "db2"]
          },
          :max_threads_running => "123",
          :max_replication_lag => "5",
          :config_path         => "/path/to/file",
          :recursion_method    => "some string",
        })
      end
    end
  end

  describe 'POST #bulk_action' do
    before (:each) do
      @meta_request = FactoryGirl.create(:meta_request_without_migrations)
    end

    context 'returns without trying to update any migrations' do
      it 'returns no error if no migrations were selected' do
        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => 3, "migrations" => []}
        error = JSON.load(response.body)["error"]
        expect(error).to eq(false)
      end

      it 'returns an error if one of the migrations has a different ddl than the meta request' do
        mig1 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id,
                                  ddl_statement: "alter table slug", cluster_name: @cluster.name)
        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => 3,
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => mig2.lock_version}]}
        error = JSON.load(response.body)["error"]
        expect(error).to eq(true)
      end

      it 'returns an error if one of the migrations has a different meta_request_id than the meta request' do
        mig1 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:pending_migration, cluster_name: @cluster.name)
        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => 3,
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => mig2.lock_version}]}
        error = JSON.load(response.body)["error"]
        expect(error).to eq(true)
      end

      it 'returns an error if one of the migrations has a different requestor than the meta request' do
        mig1 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id,
                                  requestor: "random", cluster_name: @cluster.name)
        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => 3,
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => mig2.lock_version}]}
        error = JSON.load(response.body)["error"]
        expect(error).to eq(true)
      end

      it 'returns an error if one of the migrations does not exist' do
        mig1 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id)
        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => 3,
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => 12039, :lock_version => 1}]}
        error = JSON.load(response.body)["error"]
        expect(error).to eq(true)
      end

      it 'returns an error if one of the bulk action is not authorized on one of the migrations' do
        mig1 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:completed_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => Migration.actions[:delete],
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => mig2.lock_version}]}
        error = JSON.load(response.body)["error"]
        expect(error).to eq(true)
      end

      it 'returns an error and does a rollback if one of the migs could not be updated' do
        mig1 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => Migration.actions[:delete],
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => 123145}]}
        error = JSON.load(response.body)["error"]
        expect(error).to eq(true)
      end
    end

    context 'successfully applies a bulk update' do
      it 'random example 1 - deletes two migrations' do
        login(admin: true)
        mig1 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:pending_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)

        expect(Migration.count).to eq(2)
        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => Migration.actions[:delete],
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => mig2.lock_version}]}
        error = JSON.load(response.body)["error"]
        expect(error).to eq(false)
        expect(Migration.count).to eq(0)
      end

      it 'random example 2 - enqueues two migrations' do
        login(admin: true)
        mig1 = FactoryGirl.create(:start_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:start_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)

        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => Migration.actions[:start],
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => mig2.lock_version}]}
        error = JSON.load(response.body)["error"]
        mig1.reload; mig2.reload

        expect(error).to eq(false)
        expect(mig1.status).to eq(Migration.status_groups[:enqueued])
        expect(mig1.auto_run).to eq(true)
        expect(mig2.status).to eq(Migration.status_groups[:enqueued])
        expect(mig2.auto_run).to eq(true)
      end

      it 'random example 3 - do not rollback on cancel errors' do
        login(admin: true)
        # setup so that we will try to cancel both, but one will fail
        allow_any_instance_of(Migration).to receive(:authorized_actions).and_return([:cancel])
        mig1 = FactoryGirl.create(:approval_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:copy_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)

        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => Migration.actions[:cancel],
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => mig2.lock_version}]}
        error = JSON.load(response.body)["error"]
        mig1.reload; mig2.reload

        expect(error).to eq(true)
        expect(mig1.status).to eq(Migration.status_groups[:awaiting_approval])
        expect(mig2.status).to eq(Migration.status_groups[:canceled])
      end

      it 'random example 4 - resumes two migrations' do
        login(admin: true)
        mig1 = FactoryGirl.create(:resumable_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:resumable_migration, meta_request_id: @meta_request.id, cluster_name: @cluster.name)

        post :bulk_action,
          {:id => @meta_request.id, :bulk_action => Migration.actions[:resume],
           :migrations => [{:id => mig1.id, :lock_version => mig1.lock_version},
                           {:id => mig2.id, :lock_version => mig2.lock_version}]}
        error = JSON.load(response.body)["error"]
        mig1.reload; mig2.reload

        expect(error).to eq(false)
        expect(mig1.status).to eq(Migration.status_groups[:copy_in_progress])
        expect(mig1.auto_run).to eq(true)
        expect(mig2.status).to eq(Migration.status_groups[:copy_in_progress])
        expect(mig2.auto_run).to eq(true)
      end
    end
  end

  describe 'POST #create' do
    context 'with valid attributes' do
      it 'creates a new meta request' do
        expect{
          post :create, valid_attributes
        }.to change(MetaRequest, :count).by(1)
      end

      it 'creates a new meta request and new migrations' do
        expect{
          post :create, valid_attributes
        }.to change(Migration, :count).by(2)
      end
    end

    context 'migrations belong to different apps' do
      before (:each) do
        FactoryGirl.create(:cluster, :name => "otherapp-001", :app => "otherapp")
      end

      it 'does not save a new meta request' do
        expect{
          post :create, valid_attributes(:databases => ["appname-001:test", "otherapp-001:test"])
        }.to_not change(MetaRequest, :count)
      end

      it 'does not save any new migrations' do
        expect{
          post :create, valid_attributes(:databases => ["appname-001:test", "otherapp-001:test"])
        }.to_not change(Migration, :count)
      end

      it 'populates a saved state hash' do
        expected = {
          :ddl_statement       => valid_attributes[:ddl_statement],
          :final_insert        => valid_attributes[:final_insert],
          :pr_url              => valid_attributes[:pr_url],
          :cluster_dbs         => {"appname-001" => ["test"], "otherapp-001" => ["test"]},
          :max_threads_running => "123",
          :max_replication_lag => "5",
          :config_path         => nil,
          :recursion_method    => nil,
        }
        post :create, valid_attributes(:databases => ["appname-001:test", "otherapp-001:test"])
        expect(assigns(:saved_state)).to eq(expected)
      end

      it 'populates a list of error objects' do
        expected = [
          OpenStruct.new({
            :cluster_name  => "otherapp-001",
            :database      => "test",
            :errors        => OpenStruct.new({
              :full_messages => ["cluster belongs to a different app than the first cluster"\
                                 " (otherapp vs appname)"]
            }),
          }),
        ]
        post :create, valid_attributes(:databases => ["appname-001:test", "otherapp-001:test"])
        expect(assigns(:errors)).to eq(expected)
      end

      it 'redirects to the create page' do
        post :create, valid_attributes(:databases => ["appname-001:test", "otherapp-001:test"])
        expect(response).to render_template(:new)
      end
    end

    context 'with invalid attributes for meta request' do
      it 'does not save a new meta request' do
        expect{
          post :create, valid_attributes(databases: nil)
        }.to_not change(MetaRequest, :count)
      end

      it 'does not save any new migrations' do
        expect{
          post :create, valid_attributes(databases: nil)
        }.to_not change(Migration, :count)
      end

      it 'populates a saved state hash' do
        expected = {
          :ddl_statement       => valid_attributes[:ddl_statement],
          :final_insert        => valid_attributes[:final_insert],
          :pr_url              => valid_attributes[:pr_url],
          :cluster_dbs         => {"appname-001" => []},
          :max_threads_running => "123",
          :max_replication_lag => "5",
          :config_path         => nil,
          :recursion_method    => nil,
        }
        post :create, valid_attributes(databases: nil)
        expect(assigns(:saved_state)).to eq(expected)
      end

      it 'populates a list of error objects' do
        expected = [
          OpenStruct.new({
            :cluster_name  => "appname-001",
            :database      => nil,
            :errors        => OpenStruct.new({
              :full_messages => ["database can't be blank"]
            }),
          }),
        ]
        post :create, valid_attributes(databases: nil)
        expect(assigns(:errors)).to eq(expected)
      end

      it 'redirects to the create page' do
        post :create, valid_attributes(databases: nil)
        expect(response).to render_template(:new)
      end
    end

    context 'with invalid attributes for migrations' do
      it 'does not save a new meta request' do
        expect{
          post :create, valid_attributes(ddl_statement: "blah")
        }.to_not change(MetaRequest, :count)
      end

      it 'does not save any new migrations' do
        expect{
          post :create, valid_attributes(ddl_statement: "blah")
        }.to_not change(Migration, :count)
      end

      it 'populates a saved state hash' do
        expected = {
          :ddl_statement       => "blah",
          :final_insert        => valid_attributes[:final_insert],
          :pr_url              => valid_attributes[:pr_url],
          :cluster_dbs         => {"appname-001" => ["test", "db1"]},
          :max_threads_running => "123",
          :max_replication_lag => "5",
          :config_path         => nil,
          :recursion_method    => nil,
        }
        post :create, valid_attributes(ddl_statement: "blah")
        expect(assigns(:saved_state)).to eq(expected)
      end

      it 'redirects to the create page' do
        post :create, valid_attributes(databases: nil)
        expect(response).to render_template(:new)
      end
    end
  end

  describe 'GET #edit' do
    before (:each) do
      @meta_request = FactoryGirl.create(:meta_request_without_migrations)
      get :edit, id: @meta_request
    end

    it 'renders the :edit view' do
      expect(response).to render_template :edit
    end

    it "assigns a meta request variable" do
      expect(assigns(:meta_request)).to eq(@meta_request)
    end

    it 'populates a saved state hash' do
      expected = {
        :ddl_statement       => @meta_request.ddl_statement,
        :final_insert        => @meta_request.final_insert,
        :pr_url              => @meta_request.pr_url,
        :max_threads_running => @meta_request.max_threads_running,
        :max_replication_lag => @meta_request.max_replication_lag,
        :config_path         => @meta_request.config_path,
        :recursion_method    => @meta_request.recursion_method,
      }
      expect(assigns(:saved_state)).to eq(expected)
    end

  end

  describe 'PATCH #update' do
    before :each do
      @meta_request = FactoryGirl.create(:meta_request_without_migrations)
    end

    context 'success path' do
      it 'updates the meta request' do
        patch :update, id: @meta_request, ddl_statement: "do something else", pr_url: "github.com/pr2"
        @meta_request.reload
        expect(@meta_request.ddl_statement).to eq('do something else')
      end

      it 'updates the migrations in the meta request' do
        mig1 = FactoryGirl.create(:pending_migration, ddl_statement: @meta_request.ddl_statement,
                                  meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:pending_migration, ddl_statement: @meta_request.ddl_statement,
                                  meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        new_ddl = "create table a like b"
        patch :update, id: @meta_request, ddl_statement: new_ddl, pr_url: "github.com/pr2"
        mig1.reload; mig2.reload; @meta_request.reload
        expect(mig1.ddl_statement).to eq(new_ddl)
        expect(mig2.ddl_statement).to eq(new_ddl)
        expect(@meta_request.ddl_statement).to eq(new_ddl)
        expect(assigns(:errors).length).to eq(0)
      end

      it 'redirects to the meta_request' do
        patch :update, id: @meta_request, ddl_statement: "do something else", pr_url: "github.com/pr2"
        expect(response).to redirect_to(@meta_request)
      end
    end

    context 'error path' do
      it 'does not update anything if one of the migrations is not editable' do
        mig1 = FactoryGirl.create(:pending_migration, ddl_statement: @meta_request.ddl_statement,
                                  meta_request_id: @meta_request.id, editable: false, cluster_name: @cluster.name)
        mig2 = FactoryGirl.create(:pending_migration, ddl_statement: @meta_request.ddl_statement,
                                  meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        starting_ddl = @meta_request.ddl_statement
        patch :update, id: @meta_request, ddl_statement: "create table a like b", pr_url: "github.com/pr2"
        mig1.reload; mig2.reload; @meta_request.reload
        expect(mig1.ddl_statement).to eq(starting_ddl)
        expect(mig2.ddl_statement).to eq(starting_ddl)
        expect(@meta_request.ddl_statement).to eq(starting_ddl)
        expect(assigns(:errors).length).to eq(1)
      end

      it 'does not update anything if one of the migrations has an error' do
        mig1 = FactoryGirl.create(:pending_migration, ddl_statement: @meta_request.ddl_statement,
                                  meta_request_id: @meta_request.id, cluster_name: "")
        mig2 = FactoryGirl.create(:pending_migration, ddl_statement: @meta_request.ddl_statement,
                                  meta_request_id: @meta_request.id, cluster_name: @cluster.name)
        starting_ddl = @meta_request.ddl_statement
        patch :update, id: @meta_request, ddl_statement: "create table a like b", pr_url: "github.com/pr2"
        mig1.reload; mig2.reload; @meta_request.reload
        expect(mig1.ddl_statement).to eq(starting_ddl)
        expect(mig2.ddl_statement).to eq(starting_ddl)
        expect(@meta_request.ddl_statement).to eq(starting_ddl)
        expect(assigns(:errors).length).to eq(1)
      end

      it 'populates a saved state hash' do
        expected = {
          :ddl_statement       => nil,
          :final_insert        => nil,
          :pr_url              => "github.com/pr",
          :max_threads_running => "200",
          :max_replication_lag => "1",
          :config_path         => nil,
          :recursion_method    => nil,
        }
        patch :update, id: @meta_request, ddl_statement: nil
        expect(assigns(:saved_state)).to eq(expected)
      end

      it 'redirects to the edit page' do
        patch :update, id: @meta_request, ddl_statement: nil
        expect(response).to render_template(:edit)
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'no migrations belong to the meta request (can be deleted)' do
      before :each do
        @meta_request = FactoryGirl.create(:meta_request_without_migrations)
      end

      it 'deletes the meta request' do
        expect{
          delete :destroy, id: @meta_request
        }.to change(MetaRequest, :count).by(-1)
      end

      it 'redirects to the root url' do
        delete :destroy, id: @meta_request
        expect(response).to redirect_to(root_url)
      end
    end

    context 'migrations belong to the meta request (can not be deleted)' do
      before :each do
        @meta_request = FactoryGirl.create(:meta_request_with_migrations)
      end

      it 'does not delete the meta request' do
        expect{
          delete :destroy, id: @meta_request
        }.to_not change(MetaRequest, :count)
      end

      it 'redirects to the current meta request' do
        delete :destroy, id: @meta_request
        expect(response).to redirect_to(@meta_request)
      end
    end
  end
end
