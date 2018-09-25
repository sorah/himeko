require 'open-uri'
require 'uri'
require 'json'
require 'erubi'
require 'sinatra/base'
require 'rack/protection'

require 'aws-sdk-core' # sts
require 'aws-sdk-iam'
require 'aws-sdk-dynamodb'

require 'himeko/role_manager'

module Himeko
  def self.app(*args)
    App.rack(*args)
  end

  class App < Sinatra::Base
    CONTEXT_RACK_ENV_NAME = 'himeko.ctx'
    USER_RACK_ENV_NAME = 'himeko.user'

    def self.initialize_context(config)
      {
        config: config,
      }
    end

    def self.rack(config={})
      klass = App

      context = initialize_context(config)
      lambda { |env|
        env[CONTEXT_RACK_ENV_NAME] = context
        klass.call(env)
      }
    end

    configure do
      enable :logging
    end

    set :root, File.expand_path(File.join(__dir__, '..', '..', 'app'))
    set :erb, escape_html: true

    use Rack::MethodOverride
    use Rack::Protection

    helpers do
      def context
        request.env[CONTEXT_RACK_ENV_NAME]
      end

      def conf
        context[:config]
      end

      def current_username
        name = request.env[USER_RACK_ENV_NAME]
        halt 401, "request.env[#{USER_RACK_ENV_NAME}] is missing (maybe a configuration bug!)" unless name
        name
      end

      def sts
        @sts ||= context[:sts] ||= conf[:sts] || Aws::STS::Client.new(logger: env['rack.logger'])
      end

      def iam
        @iam ||= context[:iam] ||= conf[:iam] || Aws::IAM::Client.new(logger: env['rack.logger'])
      end

      def dynamodb_table
        @dynamodb_table ||= context[:dynamodb_table] ||= conf[:dynamodb_table] ||= Aws::DynamoDB::Resource.new().table(conf.fetch(:dynamodb_table_name))
      end

      def role_manager
        @role_manager ||= context[:role_manager] ||= RoleManager.new(
          iam: iam,
          prefix: conf.fetch(:role_prefix),
          path: conf.fetch(:role_path),
          ttl: conf.fetch(:role_ttl, 86400),
          dynamodb_table: dynamodb_table,
        )
      end

      def console_session_duration
        conf.fetch(:session_duration, 3600)
      end

      def render_no_user_error
        status 403
        erb :no_user_error
      end
    end

    get '/' do
      unless session[:iam_user_existence]
        iam.get_user(user_name: current_username)
        session[:iam_user_existence] = true
      end
      erb :index
    rescue Aws::IAM::Errors::NoSuchEntity
      return render_no_user_error()
    end

    post '/console' do
      recreate = params[:recreate] == '1'
      begin
        arn = role_manager.fetch(current_username, recreate: recreate)
      rescue Aws::IAM::Errors::LimitExceeded => e
        @iam_error = e
        status 400
        return erb :iam_limit_exceeded_error
      end

      retries = 0
      resp = nil
      begin
        resp = sts.assume_role(
          duration_seconds: console_session_duration,
          role_arn: arn,
          role_session_name: current_username,
        )
      rescue Aws::STS::Errors::AccessDenied
        raise if retries > 5
        sleep 1 + (1.1**retries)
        retries += 1
        retry
      end
      json = {sessionId: resp.credentials.access_key_id, sessionKey: resp.credentials.secret_access_key, sessionToken: resp.credentials.session_token}.to_json
      signin_token = JSON.parse(open("https://signin.aws.amazon.com/federation?Action=getSigninToken&Session=#{URI.encode_www_form_component(json)}", 'r', &:read))

      url = "https://signin.aws.amazon.com/federation?Action=login&Issuer=#{URI.encode_www_form_component(request.base_url)}&Destination=#{URI.encode_www_form_component(params[:relay] || 'https://console.aws.amazon.com/console/home')}&SigninToken=#{signin_token.fetch("SigninToken")}"

      redirect url
    end

    get '/keys' do
      @keys = iam.list_access_keys(user_name: current_username)
        .access_key_metadata.map do |key_data|
          [
            key_data,
            iam.get_access_key_last_used(access_key_id: key_data.access_key_id).access_key_last_used,
          ]
        end
      erb :keys
    rescue Aws::IAM::Errors::NoSuchEntity
      return render_no_user_error()
    end

    post '/keys' do
      #\@key = Struct.new(:user_name, :access_key_id, :secret_access_key).new('foobar', 'DUMMY123', 'secret+secret')
      @key = iam.create_access_key(user_name: current_username).access_key
      erb :new_key
    rescue Aws::IAM::Errors::NoSuchEntity
      return render_no_user_error()
    end

    delete '/keys/:id' do
      iam.delete_access_key(access_key_id: params[:id], user_name: current_username)
      session[:notice] = "Access key #{params[:id]} has been deleted."
      redirect '/keys'
    rescue Aws::IAM::Errors::NoSuchEntity
      halt 404, 'NoSuchEntity'
    end

    post '/keys/:id/active' do
      iam.update_access_key(access_key_id: params[:id], user_name: current_username, status: 'Active')
      session[:notice] = "Access key #{params[:id]} has been activated."
      redirect '/keys'
    rescue Aws::IAM::Errors::NoSuchEntity
      halt 404, 'NoSuchEntity'
    end

    delete '/keys/:id/active' do
      iam.update_access_key(access_key_id: params[:id], user_name: current_username, status: 'Inactive')
      session[:notice] = "Access key #{params[:id]} has been deactivated."
      redirect '/keys'
    rescue Aws::IAM::Errors::NoSuchEntity
      halt 404, 'NoSuchEntity'
    end
  end
end
