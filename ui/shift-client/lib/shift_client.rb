require 'rest-client'
require 'json'

class ShiftClient
  attr_reader :insecure, :url
  def initialize(url: raise, ssl_cert: nil, ssl_key: nil, ssl_ca: nil, insecure: true)
    @ssl_cert = ssl_cert
    @ssl_key = ssl_key
    @ssl_ca = ssl_ca
    @insecure = insecure

    @url = url
  end

  def get_migration(migration_id)
    shift_get("/api/v1/migrations/#{migration_id}")
  end

  def create_migration(cluster, database, ddl_statement, pr_url, requestor, final_insert: nil,
                      config_path: nil, recursion_method: nil)
    params = {
      :cluster_name     => cluster,
      :database         => database,
      :ddl_statement    => ddl_statement,
      :pr_url           => pr_url,
      :requestor        => requestor,
      :final_insert     => final_insert || "",
      :config_path      => config_path || "",
      :recursion_method => recursion_method || "",
    }

    shift_post("/api/v1/migrations", params)
  end

  def generic_migration_action_post(action, options)
    params = {}
    params[:id] = options.id
    params[:lock_version] = options.lock_version if options.lock_version
    params[:runtype] = options.runtype if options.runtype
    params[:approver] = options.approver if options.approver
    params[:auto_run] = options.auto_run if options.auto_run

    shift_post("/api/v1/migrations/#{action}", params)
  end

  def delete_migration(migration_id, lock_version)
    params = {
      :lock_version => lock_version,
    }
    shift_delete("/api/v1/migrations/#{migration_id}", params)
  end

  private

  def shift_get(route, params = nil)
    headers = get_headers
    headers.merge!(params: params) if params
    begin
      response = resource_for_route(route).get(
        headers
      )
    rescue RestClient::BadRequest, RestClient::ResourceNotFound => e
      response = e.http_body
    end

    parse_response(response)
  end

  def shift_post(route, params = nil)
    begin
      response = resource_for_route(route).post(
        params.to_json,
        post_headers,
      )
    rescue RestClient::BadRequest, RestClient::ResourceNotFound => e
      response = e.http_body
    end

    parse_response(response)
  end

  def shift_delete(route, params = nil)
    # have to do some different stuff here because RestClient::Resource
    # doesn't support extra params for deleting
    headers = delete_headers
    headers.merge!(params: params) if params
    opts = {
      method: :delete,
      url: @url + route,
      headers: headers,
    }
    opts.merge!(ssl_options) unless @insecure
    begin
      response = RestClient::Request.execute(opts)
    rescue RestClient::BadRequest, RestClient::ResourceNotFound => e
      response = e.http_body
    end

    parse_response(response)
  end

  def get_headers
    {:accept => 'application/json'}
  end

  def post_headers
    get_headers.merge!(:content_type => 'application/json')
  end

  def delete_headers
    get_headers
  end

  def resource_for_route(route)
    opts = {}
    opts.merge!(ssl_options) unless @insecure
    RestClient::Resource.new(
      @url + route,
      opts
    )
  end

  def ssl_options
    {
      :ssl_client_cert => OpenSSL::X509::Certificate.new(File.read(@ssl_cert)),
      :ssl_client_key  => OpenSSL::PKey::RSA.new(File.read(@ssl_key)),
      :ssl_ca_file     => @ssl_ca,
      :verify_ssl      => OpenSSL::SSL::VERIFY_PEER,
    }
  end

  def parse_response(response)
    JSON.parse(response)
  end
end
