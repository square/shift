require 'integration_helper'
require 'shared_setup'

RSpec.describe MigrationsController, type: :controller do
  include_context "shared setup"

  let(:statuses) { Migration.status_groups }
  let(:profile) { {"developer" => {:photo => "pic.img"}} }
  let(:profile_client) { instance_double(Profile) }

  before(:each) do
    @cluster = FactoryGirl.create(:cluster, admin_review_required: false)
    FactoryGirl.create(:owner, cluster_name: @cluster.name, username: "user1")
    login
  end

  def valid_attributes(extra = {})
    {
      :cluster_name  => 'appname-001',
      :database      => 'test',
      :table         => 'users',
      :ddl_statement => 'ALTER TABLE users DROP COLUMN `c`',
      :pr_url        => 'github.com/pr',
      :final_insert  => 'INSERT INTO schema_migrations',
    }.merge(extra).with_indifferent_access
  end

  describe 'GET #index' do
    context 'with a valid parameter' do
      it 'renders the :index view' do
        get :index, {state: "pending"}
        expect(response).to render_template(:index)
      end

      it 'populates array of one state of migrations' do
        pending_migrations = FactoryGirl.create(:pending_migration)
        get :index, {state: "pending"}
        expect(assigns(:migrations)["pending"]).to eq([pending_migrations])
        expect(assigns(:migrations).keys.length).to eq(1)
      end

      it 'populates hash of one state of migration counts' do
        pending_migrations = FactoryGirl.create(:pending_migration)
        get :index, {state: "pending"}
        expect(assigns(:counts)).to eq({
          "pending"   => [pending_migrations].length,
        })
      end

      it 'sets limit to false' do
        get :index, {state: "pending"}
        expect(assigns(:limit)).to eq(false)
      end

      it 'sets show_filter to false' do
        get :index, {state: "pending"}
        expect(assigns(:show_filter)).to eq(false)
      end
    end

    context 'without a valid parameter' do
      it 'renders the :index view' do
        get :index
        expect(response).to render_template(:index)
      end

      it 'populates array of pending migrations' do
        pending_migrations = FactoryGirl.create(:pending_migration)
        get :index
        expect(assigns(:migrations)["pending"]).to eq([pending_migrations])
      end

      it 'populates array of running migrations' do
        running_migrations = FactoryGirl.create(:running_migration)
        get :index
        expect(assigns(:migrations)["running"]).to eq([running_migrations])
      end

      it 'populates array of completed migrations' do
        completed_migrations = FactoryGirl.create(:completed_migration)
        get :index
        expect(assigns(:migrations)["completed"]).to eq([completed_migrations])
      end

      it 'populates array of canceled migrations' do
        canceled_migrations = FactoryGirl.create(:canceled_migration)
        get :index
        expect(assigns(:migrations)["canceled"]).to eq([canceled_migrations])
      end

      it 'populates hash of migration counts' do
        pending_migrations = FactoryGirl.create(:pending_migration)
        running_migrations = FactoryGirl.create(:running_migration)
        completed_migrations = FactoryGirl.create(:completed_migration)
        canceled_migrations = FactoryGirl.create(:canceled_migration)
        failed_migrations = FactoryGirl.create(:failed_migration)
        get :index
        expect(assigns(:counts)).to eq({
          "pending"   => [pending_migrations].length,
          "running"   => [running_migrations].length,
          "completed" => [completed_migrations].length,
          "canceled"  => [canceled_migrations].length,
          "failed"    => [failed_migrations].length,
        })
      end

      it 'sets limit to true' do
        get :index
        expect(assigns(:limit)).to eq(true)
      end

      it 'sets show_filter to true' do
        get :index
        expect(assigns(:show_filter)).to eq(true)
      end

      it 'populates array of clusters' do
        pending_migration = FactoryGirl.create(:pending_migration)
        get :index
        expect(assigns(:cluster_names)).to eq([pending_migration.cluster.name])
      end

      it 'populates array of requestors' do
        pending_migration = FactoryGirl.create(:pending_migration)
        get :index
        expect(assigns(:requestors)).to eq([pending_migration.requestor])
      end
    end

    it 'populates a hash of migration statuses' do
      get :index
      expect(assigns(:statuses)).to eq(Statuses.all.index_by(&:status))
    end

    it 'populates cluster' do
      get :index, cluster: "my_cluster"
      expect(assigns(:cluster_name)).to eq("my_cluster")
    end

    it 'populates requestor' do
      get :index, requestor: "mike"
      expect(assigns(:requestor)).to eq("mike")
    end
  end

  describe 'GET #show' do
    before (:each) do
      allow(Profile).to receive(:new).and_return(profile_client)
      allow(profile_client).to receive(:primary_photo).and_return("pic.img")
      @migration = FactoryGirl.create(:pending_migration,
        cluster_name: @cluster.name,
        database: "testdb",
        ddl_statement: "ALTER TABLE `test` MODIFY `asdf` VARCHAR (191) NOT NULL")
      get :show, id: @migration
    end

    it 'renders the :show view' do
      expect(response).to render_template(:show)
    end

    it 'assigns the requested migration to @migration' do
      expect(response).to render_template(:show)
      expect(assigns(:migration)).to eq(@migration)
    end

    it 'assigns the status of the requested migration to @status' do
      expect(response).to render_template(:show)
      expect(assigns(:status)).to eq(Statuses.find_by_status!(@migration.status))
    end

    it 'assigns a map of user profiles to @profile' do
      expect(response).to render_template(:show)
      expect(assigns(:profile)).to eq(profile)
    end
  end

  describe 'GET #refresh_detail' do
    before (:each) do
      @migration = FactoryGirl.create(:running_migration,
        cluster_name: @cluster.name,
        database: "testdb",
        ddl_statement: "ALTER TABLE `test` MODIFY `asdf` VARCHAR (191) NOT NULL")
      get :show, id: @migration
      get :refresh_detail, id: @migration
    end

    it 'renders the migration/_detail partial' do
      expect(response).to render_template(:partial => 'migrations/_detail')
    end

    it 'assigns the requested migration to @migration' do
      expect(assigns(:migration)).to eq(@migration)
    end

    it 'assigns the status of the requested migration to @status' do
      expect(assigns(:status)).to eq(Statuses.find_by_status!(@migration.status))
    end

    it 'includes the status and copy percantage in the json body' do
      expect(response).to render_template(:partial => 'migrations/_detail')
      expect(JSON.load(response.body)["status"]).to eq(@migration.status)
      expect(JSON.load(response.body)["copy_percentage"]).to eq(@migration.copy_percentage)
    end
  end

  describe 'GET #table_stats' do
    before (:each) do
      @completed_migration1 = FactoryGirl.create(:completed_migration,
        cluster_name: @cluster.name,
        database: "testdb",
        ddl_statement: "ALTER TABLE `test` MODIFY `asdf` VARCHAR (191) NOT NULL",
        started_at: Time.new(2015, 5, 20, 2, 2, 2),
        completed_at: Time.new(2015, 5, 20, 3, 4, 5))
      @completed_migration2 = FactoryGirl.create(:completed_migration,
        cluster_name: @cluster.name,
        database: "testdb",
        ddl_statement: "ALTER TABLE `test` MODIFY `asdf` VARCHAR (191) NOT NULL",
        started_at: Time.new(2015, 6, 20, 2, 2, 2),
        completed_at: Time.new(2015, 6, 20, 4, 6, 8))
      @migration = FactoryGirl.create(:running_migration,
        cluster_name: @cluster.name,
        database: "testdb",
        ddl_statement: "ALTER TABLE `test` MODIFY `asdf` VARCHAR (191) NOT NULL")
      get :table_stats, id: @migration
    end

    it 'returns a 200 status code' do
      expect(response).to have_http_status(200)
    end

    it 'returns the correct last_alter_date' do
      expect(json["last_alter_date"]).to eq("06/20/2015")
    end

    it 'returns the correct last_alter_duration' do
      expect(json["last_alter_duration"]).to eq(7446)
    end

    it 'returns the correct average_alter_duration' do
      expect(json["average_alter_duration"]).to eq(5584.5)
    end
  end

  describe 'GET #new' do
    context "without valid parameters" do
      before (:each) do
        get :new
      end

      it 'renders the :new view' do
        expect(response).to render_template :new
      end

      it "assigns assigns a NewMigrationRequest Form to @migration" do
        expect(assigns(:migration)).to be_a(Form::NewMigrationRequest)
      end
    end

    context "with valid parameters" do
      it "sends valid params to the form" do
        get :new, :pr_url => "github.com"
        expect(assigns(:migration)).to be_a(Form::NewMigrationRequest)
        expect(assigns(:migration).pr_url).to eq("github.com")
      end
    end
  end

  describe 'GET #edit' do
    before (:each) do
      @migration = FactoryGirl.create(:pending_migration, cluster_name: @cluster.name)
      get :edit, id: @migration
    end

    it 'renders the :edit view' do
      expect(response).to render_template :edit
    end

    it "assigns assigns an EditMigrationRequest Form to @migration" do
      expect(assigns(:migration)).to be_a(Form::EditMigrationRequest)
    end
  end

  describe 'POST #create' do
    context 'with valid attributes' do
      it 'creates a new migration' do
        expect{
          post :create, form_new_migration_request: valid_attributes
        }.to change(Migration, :count).by(1)
      end

      it 'redirects to the new migration' do
        post :create, form_new_migration_request: valid_attributes
        expect(response).to redirect_to(Migration.last)
      end
    end

    context 'with invalid attributes' do
      it 'does not save a new migration' do
        expect{
          post :create, form_new_migration_request: valid_attributes(cluster_name: nil)
        }.to_not change(Migration, :count)
      end

      it 'redirects to the new migration' do
        post :create, form_new_migration_request: valid_attributes(cluster_name: nil)
        expect(response).to render_template(:new)
      end
    end
  end

  describe 'PATCH #update' do
    context 'with valid attributes' do
      before :each do
        @migration = FactoryGirl.create(:pending_migration, cluster_name: @cluster.name)
      end

      it 'updates the migration' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {ddl_statement: 'DROP TABLE `existing_table`'}
        @migration.reload
        expect(@migration.parsed[:table]).to eq('existing_table')
      end

      it 'could drop all foreign keys' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {
          ddl_statement: 'ALTER TABLE has_foreign_keys DROP FOREIGN KEY fk2, DROP FOREIGN KEY `fk1`'
        }
        @migration.reload
        expect(@migration.parsed[:stm]).to eq('ALTER TABLE has_foreign_keys DROP FOREIGN KEY _fk2 , DROP FOREIGN KEY `_fk1`')
      end

      it 'can drop table which has foreign keys' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {
          ddl_statement: 'DROP TABLE has_foreign_keys'
        }
        @migration.reload
        expect(@migration.parsed[:table]).to eq('has_foreign_keys')
      end

      it 'redirects to the migration' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {ddl_statement: 'DROP TABLE existing_table'}
        expect(response).to redirect_to(Migration.last)
      end

      it 'sets runtype to undecided' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {ddl_statement: 'DROP TABLE existing_table'}
        @migration.reload
        expect(@migration.runtype).to eq(Migration.types[:run][:undecided])
      end
    end

    context 'with invalid attributes' do
      before :each do
        @migration = FactoryGirl.create(:pending_migration, cluster_name: @cluster.name)
      end

      it 'does not update the migration' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {database: ''}
        @migration.reload
        expect(@migration.database).to eq('testdb')
      end

      it 'does not update the migration because table not exists' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {ddl_statement: 'DROP TABLE not_existing_table'}
        @migration.reload
        expect(@migration.parsed[:table]).to eq('test_table')
      end

      it 'does not update the migration because foreign keys exist' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {ddl_statement: 'ALTER TABLE has_foreign_keys DROP COLUMN asd'}
        @migration.reload
        expect(@migration.parsed[:table]).to eq('test_table')
      end

      it 'could not drop table which is referenced by foreign keys' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {
          ddl_statement: 'DROP TABLE has_foreign_keys_referenced'
        }
        @migration.reload
        expect(@migration.parsed[:table]).to eq('test_table')
      end

      it 'does not update the migration because being referenced by foreign keys' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {ddl_statement: 'DROP TABLE has_foreign_keys_refereced'}
        @migration.reload
        expect(@migration.parsed[:table]).to eq('test_table')
      end

      it 'does not update the migration because foreign keys are not all dropped' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {
          ddl_statement: 'ALTER TABLE has_foreign_keys DROP FOREIGN KEY fk2'
        }
        @migration.reload
        expect(@migration.parsed[:table]).to eq('test_table')
      end

      it 'redirects to the edit page' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {database: ''}
        expect(response).to render_template(:edit)
      end

      it 'redirects to the edit page because table not exists' do
        patch :update, id: @migration, lock_version: @migration.lock_version, form_edit_migration_request: {ddl_statement: 'DROP TABLE not_existing_table'}
        expect(response).to render_template(:edit)
      end
    end

    context 'lock_version does not match' do
      before :each do
        @migration = FactoryGirl.create(:pending_migration, cluster_name: @cluster.name)
      end

      it 'does not update the migration' do
        patch :update, id: @migration, form_edit_migration_request: {database: 'new_database', lock_version: 1}
        @migration.reload
        expect(@migration.database).to eq('testdb')
      end

      it 'redirects to the migration' do
        patch :update, id: @migration, form_edit_migration_request: {database: 'new_database', lock_version: 1}
        expect(response).to redirect_to(@migration)
      end
    end

    context 'the migration belongs to a meta request' do
      before :each do
        @migration = FactoryGirl.create(:pending_migration, meta_request_id: 1, cluster_name: @cluster.name)
      end

      it 'does not update the migration' do
        patch :update, id: @migration, form_edit_migration_request: {database: 'new_database', lock_version: 1}
        @migration.reload
        expect(@migration.database).to eq('testdb')
      end

      it 'redirects to the migration' do
        patch :update, id: @migration, form_edit_migration_request: {database: 'new_database', lock_version: 1}
        expect(response).to redirect_to(@migration)
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'on a deletable step' do
      before :each do
        login(admin: true)
        @migration = FactoryGirl.create(:deletable_migration, cluster_name: @cluster.name)
      end

      it 'deletes the migration' do
        expect{
          delete :destroy, id: @migration, lock_version: @migration.lock_version
        }.to change(Migration, :count).by(-1)
      end

      it 'redirects to the root url' do
        delete :destroy, id: @migration, lock_version: @migration.lock_version
        expect(response).to redirect_to(root_url)
      end
    end

    context 'on an undeletable step' do
      before :each do
        login(admin: true)
        @migration = FactoryGirl.create(:undeletable_migration, cluster_name: @cluster.name)
      end

      it 'does not delete the migration' do
        expect{
          delete :destroy, id: @migration, lock_version: @migration.lock_version
        }.to_not change(Migration, :count)
      end

      it 'redirects to the current migration' do
        delete :destroy, id: @migration, lock_version: @migration.lock_version
        expect(response).to redirect_to(@migration)
      end
    end

    context 'lock_version does not match' do
      before :each do
        login(admin: true)
        @migration = FactoryGirl.create(:deletable_migration, cluster_name: @cluster.name)
      end

      it 'does not delete the migration' do
        expect{
          delete :destroy, id: @migration, lock_version: 1
        }.to_not change(Migration, :count)
      end

      it 'redirects to the current migration' do
        delete :destroy, id: @migration, lock_version: 1
        expect(response).to redirect_to(@migration)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:undeletable_migration, cluster_name: @cluster.name)
      end

      it 'does not delete the migration' do
        expect{
          delete :destroy, id: @migration, lock_version: @migration.lock_version
        }.to_not change(Migration, :count)
      end

      it 'redirects to 401' do
        delete :destroy, id: @migration, lock_version: @migration.lock_version
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'POST #approve' do
    context 'on the approve step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name)
        post :approve, id: @migration, lock_version: @migration.lock_version, runtype: 1
        @migration.reload
      end

      it 'approves the migration' do
        expect(@migration.status).to eq(statuses[:awaiting_start])
      end

      it 'sets the runtype' do
        expect(@migration.runtype).to eq(1)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'not on the approve step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:start_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :approve, id: @migration
        @migration.reload
      end

      it 'does not approve the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'user cannot approve dangerous short run, but they are trying to' do
      before :each do
        login(admin: false)

        FactoryGirl.create(:owner, cluster_name: @cluster.name, username: "developer")
        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name,
                                        table_rows_start: 20000, requestor: "someone")
        @starting_status = @migration.status
        allow_any_instance_of(Migration).to receive(:parsed).and_return({:run => :maybeshort})
        post :approve, id: @migration, runtype: Migration.types[:run][:short]
        @migration.reload
      end

      it 'does not approve the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end

    context 'user cannot approve dangerous short run, but the table is really small so it is okay' do
      before :each do
        login(admin: false)

        FactoryGirl.create(:owner, cluster_name: @cluster.name, username: "developer")
        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name,
                                        table_rows_start: 200, requestor: "someone")
        @starting_status = @migration.status
        allow_any_instance_of(Migration).to receive(:parsed).and_return({:run => :maybeshort})
        post :approve, id: @migration, runtype: Migration.types[:run][:short], lock_version: @migration.lock_version
        @migration.reload
      end

      it 'approves the migration' do
        expect(@migration.status).to eq(statuses[:awaiting_start])
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'user cannot approve dangerous nocheckalter, but they are trying to' do
      before :each do
        login(admin: false)

        FactoryGirl.create(:owner, cluster_name: @cluster.name, username: "developer")
        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name,
                                        requestor: "someone")
        @starting_status = @migration.status
        allow_any_instance_of(Migration).to receive(:parsed).and_return({:run => :maybenocheckalter})
        post :approve, id: @migration, runtype: Migration.types[:run][:nocheckalter]
        @migration.reload
      end

      it 'does not approve the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :approve, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'does not approve the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'POST #unapprove' do
    context 'on the start step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:start_migration, cluster_name: @cluster.name)
        post :unapprove, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'unapproves the migration' do
        expect(@migration.status).to eq(statuses[:awaiting_approval])
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'not on the start step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :unapprove, id: @migration
        @migration.reload
      end

      it 'does not unapprove the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:start_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :unapprove, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'does not unapprove the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'POST #start' do
    context 'on the start step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:start_migration, cluster_name: @cluster.name)
        post :start, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'starts the migration' do
        expect(@migration.status).to eq(statuses[:copy_in_progress])
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'not on the start step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :start, id: @migration
        @migration.reload
      end

      it 'does not start the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:start_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :start, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'does not start the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'POST #pause' do
    context 'on the copy step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:copy_migration, cluster_name: @cluster.name)
        post :pause, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'puts the migration in the pausing step' do
        expect(@migration.status).to eq(statuses[:pausing])
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'not on the copy step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :pause, id: @migration
        @migration.reload
      end

      it 'does not pause the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:copy_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :pause, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'does not pause the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'POST #rename' do
    context 'on the rename step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:awaiting_rename_migration, cluster_name: @cluster.name)
        post :rename, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'puts the migration in the renaming step' do
        expect(@migration.status).to eq(statuses[:rename_in_progress])
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'not on the rename step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :rename, id: @migration
        @migration.reload
      end

      it 'does not rename the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:copy_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :rename, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'does not rename the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'POST #resume' do
    context 'on a resumable step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:resumable_migration, cluster_name: @cluster.name)
        post :resume, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'puts the migration in the copy step' do
        expect(@migration.status).to eq(statuses[:copy_in_progress])
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'not on a resumable step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :resume, id: @migration
        @migration.reload
      end

      it 'does not resume the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:resumable_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :resume, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'does not resume the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'POST #dequeue' do
    context 'on a dequeueable step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:enqueued_migration, cluster_name: @cluster.name)
        post :dequeue, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'puts the migration in the awaiting start step' do
        expect(@migration.status).to eq(statuses[:awaiting_start])
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'not on a dequeueable step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:approval_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :dequeue, id: @migration
        @migration.reload
      end

      it 'does not dequeue the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:enqueued_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :dequeue, id: @migration, lock_version: @migration.lock_version
        @migration.reload
      end

      it 'does not dequeue the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'POST #cancel' do
    context 'on a cancelable step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:cancelable_migration, cluster_name: @cluster.name)
        post :cancel, id: @migration
        @migration.reload
      end

      it 'cancels the migration' do
        expect(@migration.status).to eq(statuses[:canceled])
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'not on a cancelable step' do
      before :each do
        login(admin: true)

        @migration = FactoryGirl.create(:noncancelable_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :cancel, id: @migration
        @migration.reload
      end

      it 'does not cancel the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to the current migration' do
        expect(response).to redirect_to(@migration)
      end
    end

    context 'access denied' do
      before :each do
        @migration = FactoryGirl.create(:cancelable_migration, cluster_name: @cluster.name)
        @starting_status = @migration.status
        post :cancel, id: @migration
        @migration.reload
      end

      it 'does not cancel the migration' do
        expect(@migration.status).to eq(@starting_status)
      end

      it 'redirects to 401' do
        expect(response.status).to eq(401)
      end
    end
  end
end
