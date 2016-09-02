require 'mysql_helper'

class StubMysql
  attr_accessor :cluster

  def initialize(cluster)
    @cluster = cluster
  end
end

RSpec.shared_context "shared setup", :a => :b do
  before do
    allow(MysqlHelper).to receive(:new) do |cluster|
      StubMysql.new cluster
    end

    allow_any_instance_of(StubMysql).to receive(:table_exists?) do |this, mode, database, table|
      if mode == :table && this.cluster == 'appname-001' && database == 'test' && table == 'users'
        true
      elsif mode == :table && this.cluster == 'appname-001' && database == 'db1' && table == 'users'
        true
      elsif mode == :table && this.cluster == 'appname-001' && database == 'testdb' && table == 'test_table'
        true
      elsif mode == :table && this.cluster == 'appname-001' && database == 'testdb' && table == 'existing_table'
        true
      elsif mode == :table && this.cluster == 'appname-001' && database == 'testdb' && table == 'non_existing_table'
        true
      elsif mode == :table && this.cluster == 'appname-001' && database == 'testdb' && table == 'has_foreign_keys'
        true
      elsif mode == :table && this.cluster == 'appname-001' && database == 'testdb' && table == 'has_foreign_keys_referenced'
        true
      else
        false
      end
    end
    allow_any_instance_of(StubMysql).to receive(:databases) do |this|
      if this.cluster == 'appname-001'
        ['testdb']
      else
        []
      end
    end
    allow_any_instance_of(StubMysql).to receive(:foreign_keys) do |this, database, table|
      if table == 'has_foreign_keys'
        ['fk1', 'fk2']
      else
        []
      end
    end
    allow_any_instance_of(StubMysql).to receive(:has_referenced_foreign_keys?) do |this, database, table|
      table == 'has_foreign_keys_referenced'
    end
    allow_any_instance_of(StubMysql).to receive(:version) do |this|
      '5.5'
    end
    allow_any_instance_of(StubMysql).to receive(:avoid_temporal_upgrade?) do |this|
      true
    end
  end
end
