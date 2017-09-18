require 'unit_helper'
require 'active_support/core_ext/hash'
require 'shared_setup'

require 'form/migration_request'
require 'form/new_migration_request'

RSpec::Matchers.define :have_error_on do |expected|
  match do |actual|
    actual.errors[expected].any?
  end
end

RSpec.describe Form::NewMigrationRequest do
  include_context "shared setup"

  def build(extra = {})
    described_class.new({
      cluster_name:        "appname-001",
      database:            "test",
      ddl_statement:       "ALTER TABLE users DROP COLUMN `c`",
      pr_url:              "github.com/pr",
      max_threads_running: "123",
      max_replication_lag: "5",
      config_path:         "/path/to/file",
      recursion_method:    "string here",
      final_insert:        "INSERT INTO schema_migrations",
    }.merge(extra).with_indifferent_access)
  end

  before (:each) do
    # this is the list of clusters that the migration cluster is validated against
    @cluster = FactoryGirl.create(:cluster)
    allow(Form::MigrationRequest).to receive(:all_clusters).and_return([@cluster])
  end

  describe "validations" do
    it "is valid with default attributes" do
      request = build
      expect(request.errors.full_messages).to eq([])
    end

    it 'validates presence of cluster_name' do
      request = build(cluster_name: nil)
      expect(request.valid?).to eq(false)
      expect(request).to have_error_on(:cluster_name)
    end

    it "validates type of cluster_name" do
      request = build(cluster_name: "non_existant")
      expect(request.valid?).to eq(false)
      expect(request).to have_error_on(:cluster_name)
    end

    it 'validates presence of database' do
      request = build(database: nil)
      expect(request.valid?).to eq(false)
      expect(request).to have_error_on(:database)
    end

    it 'validates presence of ddl statement' do
      request = build(ddl_statement: nil)
      expect(request.valid?).to eq(false)
      expect(request).to have_error_on(:ddl_statement)
    end

    it 'validates presence of pr url' do
      request = build(pr_url: nil)
      expect(request.valid?).to eq(false)
      expect(request).to have_error_on(:pr_url)
    end

    it 'validates format of pr url' do
      request = build(pr_url: "javascript:alert('hi')")
      expect(request.valid?).to eq(false)
      expect(request).to have_error_on(:pr_url)
    end

    it 'validates positive integerness of max threads running' do
      request = build(max_threads_running: -1)
      expect(request.valid?).to eq(false)
      expect(request).to have_error_on(:max_threads_running)
    end

    it 'validates positive integerness of max replication lag' do
      request = build(max_replication_lag: -1)
      expect(request.valid?).to eq(false)
      expect(request).to have_error_on(:max_replication_lag)
    end
  end

  describe '#save' do
    let(:new_migration) { double("tracer") }
    let!(:dao) { class_double('Migration',
      :create! => new_migration,
      :types => {
        run: {undecided: 0, long: 1, short: 2, maybeshort: 3},
        mode: {table: 0, view: 1},
        action: {create: 0, drop: 1, alter: 2},
      }
    ).as_stubbed_const }

    it 'saves record and returns true' do
      expect(dao).to receive(:create!).with(
        cluster_name:         "appname-001",
        database:             "test",
        ddl_statement:        "ALTER TABLE users DROP COLUMN `c`",
        pr_url:               "github.com/pr",
        final_insert:         "INSERT INTO schema_migrations",
        requestor:            nil,
        meta_request_id:      nil,
        runtype:              0,
        initial_runtype:      1,
        max_threads_running: "123",
        max_replication_lag: "5",
        config_path:         "/path/to/file",
        recursion_method:    "string here",
      )
      build.save
    end

    it 'returns false when request is invalid' do
      request = build(cluster_name: nil)
      expect(request.save).to eq(false)
    end
  end
end
