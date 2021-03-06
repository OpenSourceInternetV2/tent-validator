require 'tent-validator/version'
require 'tentd/utils'
require 'api-validator'
require 'faraday'
require 'tent-client'
require 'thread'
require 'benchmark'

module TentValidator

  require 'tent-validator/spec'

  require 'tent-validator/runner'

  require 'tent-validator/faraday/validator_rack_adapter'
  require 'tent-validator/faraday/validator_net_http_adapter'

  SetupFailure = Class.new(StandardError) do
    attr_reader :response, :results, :validator
    def initialize(message, response, results=nil, validator=nil)
      super(message)
      results = [results] if results && !(Array === results)
      @response, @results, @validator = response, results, validator
    end
  end

  class << self
    attr_accessor :remote_app_authorization_credentials, :remote_app_credentials, :remote_server_meta, :remote_entity_uri, :local_database_url, :local_server, :local_server_port, :mutex
  end

  def self.setup!(options = {})
    self.local_database_url = options[:tent_database_url] || ENV['TENT_DATABASE_URL']

    ENV['DB_LOGFILE'] ||= '/dev/null'
    ENV['REDIS_NAMESPACE'] = 'validator.tentd.worker'
    ENV['DATABASE_URL'] = self.local_database_url

    require 'tentd/worker'
    sidekiq_pid = TentD::Worker.run_server
    puts "Validator sidekiq server running (pid: #{sidekiq_pid})"

    at_exit do
      Process.kill("INT", sidekiq_pid)
    end

    require 'tentd'
    TentD.setup!(:database_url => self.local_database_url)
    TentD::Worker.configure_client

    require 'tent-validator/tentd/model/user'

    self.local_server = wrap_local_server(TentD::API.new)
    self.mutex = Mutex.new

    self.remote_entity_uri = options.delete(:remote_entity_uri)
  end

  def self.remote_registration
    client = TentClient.new(remote_entity_uri,
      :faraday_adapter => remote_adapter
    )

    res =  TentClient::Discovery.discover(client, remote_entity_uri, :return_response => true)

    unless res
      raise SetupFailure.new("Failed to perform discovery on remote server!", Faraday::Response.new({}))
    end

    unless res.status == 200
      raise SetupFailure.new("Failed to fetch meta post from remote server!", res)
    end

    self.remote_server_meta = res.body['post']

    begin
      res = client.post.create(
        :type => "https://tent.io/types/app/v0#",
        :content => {
          :name => "Validator",
          :description => "Tent 0.3 Protocol Validator",
          :url => "http://localhost/validator",
          :redirect_uri => "null://validator/callback",
          :types => {
            :read => %w( all ),
            :write => %w( all )
          },
          :scopes => %w( import permissions )
        },
        :permissions => {
          :public => false
        }
      )
    rescue Faraday::Error::ConnectionFailed
      raise SetupFailure.new("Failed to register app on remote server!", Faraday::Response.new({}))
    end

    unless res.success?
      raise SetupFailure.new("Failed to register app on remote server!", res)
    end

    app = res.body['post']

    links = TentClient::LinkHeader.parse(res.headers['Link']).links
    credentials_url = links.find { |link| link[:rel] == 'https://tent.io/rels/credentials' }
    credentials_url = credentials_url.uri if credentials_url

    unless credentials_url
      raise SetupFailure.new("App credentials not linked!", res)
    end

    begin
      res = client.http.get(credentials_url)
    rescue Faraday::Error::ConnectionFailed
      raise SetupFailure.new("Failed to fetch app credentials from #{credentials_url.to_s.inspect}!", Faraday::Response.new({}))
    end

    unless res.success?
      raise SetupFailure.new("Failed to fetch app credentials!", res)
    end

    app_credentials = {
      :id => res.body['post']['id'],
      :hawk_key => res.body['post']['content']['hawk_key'],
      :hawk_algorithm => res.body['post']['content']['hawk_algorithm']
    }

    TentValidator.remote_app_credentials = app_credentials

    app_client = TentClient.new(remote_entity_uri,
      :faraday_adapter => remote_adapter,
      :server_meta => remote_server_meta,
      :credentials => app_credentials
    )

    oauth_uri = client.oauth_redirect_uri(:client_id => app['id'])

    begin
      res = client.http.get(oauth_uri.to_s)
      return (self.remote_app_authorization_credentials = nil) unless res.status == 302
      oauth_code = Spec.parse_params(URI(res.headers["Location"]).query)['code']
    rescue Faraday::Error::ConnectionFailed
      raise SetupFailure.new("OAuth request failed (#{oauth_uri.to_s.inspect})!", Faraday::Response.new({}))
    end

    begin
      if res.status == 302 && (res = app_client.oauth_token_exchange(:code => oauth_code)) && res.success?
        oauth_credentials = res.body
        self.remote_app_authorization_credentials = {
          :id => oauth_credentials['access_token'],
          :hawk_key => oauth_credentials['hawk_key'],
          :hawk_algorithm => oauth_credentials['hawk_algorithm']
        }
      else
        self.remote_app_authorization_credentials = nil
      end
    rescue Faraday::Error::ConnectionFailed
      raise SetupFailure.new("OAuth token exchange failed!", Faraday::Response.new({}))
    end
  end

  def self.manipulate_requests
    @manipulate_requests ||= Hash.new
  end

  def self.watch_local_requests
    @watch_local_requests ||= Hash.new
  end

  def self.pending_local_requests
    @pending_local_requests ||= []
  end

  def self.async_local_request_expectations
    @async_local_request_expectations ||= []
  end

  def self.local_requests
    @local_requests ||= []
  end

  def self.webhooks
    @webhooks ||= {}
  end

  def self.wrap_local_server(app)
    not_found = lambda {
      [404, { 'Content-Type' => 'text/plain' }, ['']]
    }

    lambda do |env|
      if env['PATH_INFO'] =~ %r{\A(/([^/]+)/tent)(.*)}
        env['ORIGINAL_PATH_INFO'] = env['PATH_INFO']
        env['PATH_INFO'] = $3.to_s
        env['SCRIPT_NAME'] = $1.to_s

        user_id = $2
        if env['current_user'] = TentD::Model::User.first(:public_id => user_id)
          local_request_key = env['current_user'].id

          middleware = nil
          unless env['HTTP_VALIDATOR_REQUEST'] == 'true'
            TentValidator.mutex.synchronize do
              middleware = TentValidator.manipulate_requests[local_request_key]
            end
          end

          if middleware
            status, headers, body = middleware.call(env, app)
          else
            status, headers, body = app.call(env)
          end
        else
          return not_found.call
        end
      elsif env['PATH_INFO'] =~ %r{\A/([^/]+)/webhooks/?\Z}
        webhook_id = $1
        if webhook = TentValidator.webhooks[webhook_id]
          local_request_key = webhook_id
          status, headers, body = webhook[:response]
        else
          return not_found.call
        end
      else
        return not_found.call
      end

      unless env['HTTP_VALIDATOR_REQUEST'] == 'true'
        TentValidator.mutex.synchronize do
          if TentValidator.watch_local_requests[local_request_key]
            env['REQUEST_BODY'] ||= begin
              _body = env['rack.input'].read
              env['rack.input'].rewind
              _body
            end
            TentValidator.pending_local_requests << [env, [status, headers, body]]
          elsif TentValidator.async_local_request_expectations.any?
            env['REQUEST_BODY'] = env['rack.input'].read
            env['rack.input'].rewind

            TentValidator.local_requests << [env, [status, headers, body]]
          end
        end
      end

      [status, headers, body]
    end
  end

  def self.run_local_server!
    return if @local_server_running

    boot_time = Benchmark.realtime do

      # get random port
      require 'socket'
      tmp_socket = Socket.new(:INET, :STREAM)
      tmp_socket.bind(Addrinfo.tcp("127.0.0.1", 0))
      tentd_host, tentd_port = tmp_socket.local_address.getnameinfo
      tmp_socket.close

      tentd_thread = Thread.new do
        require 'puma/cli'

        puts "Booting Validator Tent server on port #{tentd_port}..."

        cli = Puma::CLI.new ['--port', tentd_port.to_s]
        local_server = self.local_server
        cli.instance_eval { @options[:app] = local_server; @options[:quiet] = true }
        cli.run
      end

      # wait until tentd server boots
      @local_server_running = false
      until @local_server_running
        begin
          Socket.tcp("127.0.0.1", tentd_port) do |connection|
            @local_server_running = true
            connection.close
          end
        rescue Errno::ECONNREFUSED
        end
      end

      TentValidator.local_server_port = tentd_port

    end

    puts "Server booted in #{boot_time}s"

    TentValidator.local_server_port
  end

  def self.remote_adapter
    @remote_adapter ||= :validator_net_http
  end

  def self.local_adapter
    @local_adapter ||= [:validator_rack, self.local_server]
  end

  def self.validators
    @validators ||= []
  end

end
