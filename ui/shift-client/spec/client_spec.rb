require 'shift_client'
require 'ostruct'

describe ShiftClient do
  let(:shift_client) { ShiftClient.new(url: "http://localhost:3000", insecure: true) }
  let(:get_headers) { {:accept => "application/json"} }
  let(:post_headers) { get_headers.merge({:content_type => "application/json"}) }
  let(:delete_headers) { get_headers }
  let(:migration_id) { 3 }
  let(:cluster) { "cluster-001" }
  let(:database) { "db_01" }
  let(:ddl_statement) { "alter table slug" }
  let(:pr_url) { "github.com/pr" }
  let(:requestor) { "michael" }
  let(:final_insert) { "" }
  let(:config_path) { "" }
  let(:recursion_method) { "" }
  let(:lock_version) { 7 }
  let(:runtype) { "long" }
  let(:approver) { "frank" }

  it "#get_migration" do
    path = shift_client.url + "/api/v1/migrations/#{migration_id}"
    resource_double = instance_double(RestClient::Resource)
    expect(RestClient::Resource).to receive(:new).with(path, {}).and_return(resource_double)
    expect(resource_double).to receive(:get).with(get_headers).and_return("{}")
    expect(shift_client.get_migration(migration_id)).to eq({})
  end

  it "#create_migration" do
    path = shift_client.url + "/api/v1/migrations"
    params = {
      :cluster_name     => cluster,
      :database         => database,
      :ddl_statement    => ddl_statement,
      :pr_url           => pr_url,
      :requestor        => requestor,
      :final_insert     => final_insert,
      :config_path      => config_path,
      :recursion_method => recursion_method,
    }
    resource_double = instance_double(RestClient::Resource)
    expect(RestClient::Resource).to receive(:new).with(path, {}).and_return(resource_double)
    expect(resource_double).to receive(:post).with(params.to_json, post_headers).and_return("{}")
    expect(shift_client.create_migration(cluster, database, ddl_statement, pr_url, requestor)).to eq({})
  end

  it "#generic_migration_action_post" do
    action = "approve"
    options = OpenStruct.new \
      :id           => migration_id,
      :lock_version => lock_version,
      :runtype      => runtype,
      :approver     => approver
    path = shift_client.url + "/api/v1/migrations/" + action
    resource_double = instance_double(RestClient::Resource)
    expect(RestClient::Resource).to receive(:new).with(path, {}).and_return(resource_double)
    expect(resource_double).to receive(:post).with(options.to_h.to_json, post_headers).and_return("{}")
    expect(shift_client.generic_migration_action_post(action, options)).to eq({})
  end

  it "#delete_migration" do
    path = shift_client.url + "/api/v1/migrations/#{migration_id}"
    params = {:lock_version => lock_version}
    opts = {
      method: :delete,
      url: path,
      headers: delete_headers.merge!({params: params}),
    }
    expect(RestClient::Request).to receive(:execute).with(opts).and_return("{}")
    expect(shift_client.delete_migration(migration_id, lock_version)).to eq({})
  end
end
