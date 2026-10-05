# frozen_string_literal: true

require 'json'
require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    # SPS Commerce identity runs on Auth0. The endpoints below come from
    # https://auth.spscommerce.com/.well-known/openid-configuration.
    #
    # An SPS app has a production key and a sandbox key. Both authenticate against
    # the same host, so the strategy does not need to know which one it holds:
    # register it twice with different names to offer both (see the README).
    class SpsCommerce < OmniAuth::Strategies::OAuth2
      DEFAULT_SITE = 'https://auth.spscommerce.com'
      # Auth0 issues an opaque, userinfo-only access token unless the authorize
      # request names an API audience.
      DEFAULT_AUDIENCE = 'api://api.spscommerce.com/'
      # offline_access is what makes Auth0 return a refresh token.
      DEFAULT_SCOPE = 'openid profile email offline_access'

      option :name, 'sps_commerce'

      option :client_options, {
        site: DEFAULT_SITE,
        authorize_url: '/authorize',
        token_url: '/oauth/token',
        # Auth0 accepts client_secret_post and client_secret_basic; keep the
        # credentials in the body, as the other Dropstream strategies do.
        auth_scheme: :request_body
      }

      option :scope, DEFAULT_SCOPE
      option :audience, DEFAULT_AUDIENCE

      option :authorize_options, %i[scope audience prompt login_hint]

      # Options a request may set for itself, e.g.
      # /auth/sps_commerce?login_hint=user@example.com
      REQUEST_AUTHORIZE_OPTIONS = %w[prompt login_hint].freeze

      uid { user_claims['sub'] }

      info do
        {
          name: user_claims['name'],
          email: user_claims['email'],
          nickname: user_claims['nickname']
        }
      end

      extra do
        {
          'params' => access_token.params.except('id_token'),
          'claims' => user_claims,
          'access_token_claims' => access_token_claims
        }
      end

      def authorize_params
        super.tap do |params|
          REQUEST_AUTHORIZE_OPTIONS.each do |key|
            value = request.params[key]
            params[key.to_sym] = value unless value.nil? || value == ''
          end
        end
      end

      # OmniAuth::Strategy#callback_url appends the callback request's own query
      # string, and Auth0 requires redirect_uri to match an allowed callback URL
      # exactly. omniauth 2's `callback_path` already carries SCRIPT_NAME, so mount
      # prefixes must not be added again.
      def callback_url
        options[:callback_url] || (full_host + callback_path)
      end

      private

      # Claims for the signed-in user: from the id_token (granted by the openid
      # scope), otherwise from the access token. The payload is read without
      # verifying the signature, which is acceptable only because the token
      # arrives directly from auth.spscommerce.com over TLS, never from the browser.
      def user_claims
        @user_claims ||= decode_jwt_claims(access_token.params['id_token']) || access_token_claims
      end

      # The API access token's claims, which carry the SPS-specific ones (for
      # example the organization). Empty when the token is opaque.
      def access_token_claims
        @access_token_claims ||= decode_jwt_claims(access_token.token) || {}
      end

      def decode_jwt_claims(jwt)
        payload = jwt.to_s.split('.')[1]
        return nil if payload.nil? || payload.empty?

        # Base64url-decode by hand; the base64 gem left Ruby's default gems in 3.4.
        json = (payload.tr('-_', '+/') + '=' * (-payload.length % 4)).unpack1('m')
        claims = JSON.parse(json)
        claims.is_a?(Hash) ? claims : nil
      rescue ArgumentError, JSON::ParserError, EncodingError
        nil
      end
    end
  end
end
