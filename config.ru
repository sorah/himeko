require 'bundler/setup'
require 'securerandom'

require 'omniauth'

require 'himeko'

if ENV['RACK_ENV'] == 'production'
  raise 'Set $SECRET_KEY_BASE' unless ENV['SECRET_KEY_BASE']
end

dev = ENV.fetch('RACK_ENV', 'development') == 'development'

use(
  Rack::Session::Cookie,
  key: 'himekosess',
  expire_after: 3600,
  secure: ENV.fetch('HIMEKO_SECURE_SESSION', ENV['RACK_ENV'] == 'production' ? '1' : nil) == '1',
  secret: ENV.fetch('SECRET_KEY_BASE', SecureRandom.base64(256)),
)

provider = nil
case
when ENV['HIMEKO_GITHUB_KEY'] && ENV['HIMEKO_GITHUB_SECRET']
  require 'omniauth-github'
  gh_client_options = {}
  if ENV['HIMEKO_GITHUB_HOST']
    gh_client_options[:site] = "#{ENV['HIMEKO_GITHUB_HOST']}/api/v3"
    gh_client_options[:authorize_url] = "#{ENV['HIMEKO_GITHUB_HOST']}/login/oauth/authorize"
    gh_client_options[:token_url] = "#{ENV['HIMEKO_GITHUB_HOST']}/login/oauth/access_token"
  end

  gh_scope = ''
  if ENV['HIMEKO_GITHUB_TEAMS']
    gh_scope = 'read:org'
  end

  use OmniAuth::Builder do
    provider(:github, ENV['HIMEKO_GITHUB_KEY'], ENV['HIMEKO_GITHUB_SECRET'], client_options: gh_client_options, scope: gh_scope)
  end
  provider = :github
when ENV['HIMEKO_GOOGLE_KEY'] && ENV['HIMEKO_GOOGLE_SECRET']
  require 'omniauth-google-oauth2'
  use OmniAuth::Builder do
    provider(:google_oauth2, ENV['HIMEKO_GOOGLE_KEY'], ENV['HIMEKO_GOOGLE_SECRET'], hd: ENV['HIMEKO_GOOGLE_HD'])
  end
  provider = :google_oauth2
when dev
  use OmniAuth::Builder do
    provider(:developer, fields: %i(uid), uid_field: :uid)
  end
  provider = :developer
end

use(Class.new do
  def initialize(app, provider)
    @app = app
    @provider = provider
  end

  def call(env)
    return process_callback(env) if env['omniauth.auth']
    session = env.fetch('rack.session')

    user = env['himeko.user'] = session[:user]
    unless user
      session[:back_to] ||= env['PATH_INFO']
      return [302, {'Location' => "/auth/#{@provider}"}, []]
    end

    @app.call env
  end

  def process_callback(env)
    session = env.fetch('rack.session')
    auth = env.fetch('omniauth.auth')
    case auth.fetch(:provider)
    when 'github'
      session[:user] = auth.fetch(:info).fetch(:nickname)
    when 'google_oauth2'
      session[:user] = auth.fetch(:info).fetch(:email).split(?@,2)[0]
    when 'developer'
      session[:user] = auth.fetch(:uid)
    end
    return [302, {'Location' => session.delete(:back_to) || '/'}, []]
  end
end, provider)

config = {
  role_path: ENV.fetch('HIMEKO_ROLE_PATH', '/user-role/'),
  role_prefix: ENV.fetch('HIMEKO_ROLE_PREFIX', 'user_'),
  dynamodb_table_name: ENV.fetch('HIMEKO_DYNAMODB_TABLE'),
  session_duration: ENV.fetch('HIMEKO_SESSION_DURATION', 3600).to_i,
}

run Himeko.app(config)
