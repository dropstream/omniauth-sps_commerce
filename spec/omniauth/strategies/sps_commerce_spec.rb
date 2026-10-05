# frozen_string_literal: true

RSpec.describe OmniAuth::Strategies::SpsCommerce do
  let(:inner_app) { ->(_env) { [200, {}, ["Hello."]] } }
  let(:strategy_options) { {} }
  let(:strategy) { described_class.new(inner_app, "client_id", "client_secret", **strategy_options) }

  def app
    described_class.new(inner_app, "client_id", "client_secret", **strategy_options)
  end

  # An unsigned JWT carrying the given claims; the strategy never verifies
  # signatures, so "signature" stands in for one.
  def encode_jwt(claims)
    payload = [claims.to_json].pack("m0").tr("+/", "-_").delete("=")
    "eyJhbGciOiJSUzI1NiJ9.#{payload}.signature"
  end

  describe "#client_options" do
    subject(:client_options) { strategy.options.client_options }

    it "points at the SPS Commerce auth site" do
      expect(client_options.site).to eq("https://auth.spscommerce.com")
    end

    it "has the Auth0 authorize and token urls" do
      expect(client_options.authorize_url).to eq("/authorize")
      expect(client_options.token_url).to eq("/oauth/token")
    end

    # oauth2 >= 2.0 defaults to :basic_auth, which would move the client
    # credentials out of the token request body.
    it "sends client credentials in the request body" do
      expect(client_options.auth_scheme).to eq(:request_body)
    end
  end

  describe "the request phase" do
    around do |example|
      previous = OmniAuth.config.request_validation_phase
      OmniAuth.config.request_validation_phase = proc {}
      example.run
      OmniAuth.config.request_validation_phase = previous
    end

    def authorize_location(path = "/auth/sps_commerce", params = {})
      post path, params, "rack.session" => {}
      expect(last_response.status).to eq(302)
      URI.parse(last_response.headers["Location"])
    end

    def authorize_query(...)
      URI.decode_www_form(authorize_location(...).query).to_h
    end

    it "redirects to the SPS Commerce authorize endpoint" do
      location = authorize_location

      expect("#{location.scheme}://#{location.host}#{location.path}")
        .to eq("https://auth.spscommerce.com/authorize")
      expect(URI.decode_www_form(location.query).to_h)
        .to include("client_id" => "client_id", "response_type" => "code")
    end

    it "requests a refresh token and the user's identity by default" do
      expect(authorize_query["scope"]).to eq("openid profile email offline_access")
    end

    it "requests the SPS API audience by default" do
      expect(authorize_query["audience"]).to eq("api://api.spscommerce.com/")
    end

    context "when the audience is configured" do
      let(:strategy_options) { {audience: "api://sandbox.example/"} }

      it "passes the configured audience" do
        expect(authorize_query["audience"]).to eq("api://sandbox.example/")
      end
    end

    context "when the site is overridden" do
      let(:strategy_options) { {client_options: {site: "https://auth.example.com"}} }

      it "redirects to the configured auth site" do
        expect(authorize_location.host).to eq("auth.example.com")
      end
    end

    describe "per-request authorize params" do
      it "passes login_hint through to the authorize url" do
        expect(authorize_query("/auth/sps_commerce", "login_hint" => "user@example.com")["login_hint"])
          .to eq("user@example.com")
      end

      it "passes prompt through to the authorize url" do
        expect(authorize_query("/auth/sps_commerce", "prompt" => "login")["prompt"]).to eq("login")
      end

      it "does not let a request change the audience" do
        expect(authorize_query("/auth/sps_commerce", "audience" => "https://evil.example.com")["audience"])
          .to eq("api://api.spscommerce.com/")
      end

      it "does not pass arbitrary request params through" do
        query = authorize_query("/auth/sps_commerce", "redirect_uri" => "https://evil.example.com")

        expect(query["redirect_uri"]).to eq("http://example.org/auth/sps_commerce/callback")
      end
    end

    # Production and sandbox keys are separate registrations of the same strategy.
    context "when registered under another name" do
      let(:strategy_options) { {name: "sps_commerce_sandbox"} }

      it "answers on its own path and callback" do
        query = authorize_query("/auth/sps_commerce_sandbox")

        expect(query["redirect_uri"]).to eq("http://example.org/auth/sps_commerce_sandbox/callback")
      end
    end
  end

  describe "the callback phase" do
    let(:session) { {"omniauth.state" => "abc123"} }
    let(:token_url) { "https://auth.spscommerce.com/oauth/token" }
    let(:access_token_claims) do
      {"sub" => "auth0|access-sub", "aud" => ["api://api.spscommerce.com/"],
       "https://auth.spscommerce.com/orgId" => "org-123"}
    end
    let(:token_response_body) do
      {
        token_type: "Bearer",
        expires_in: 86_400,
        access_token: encode_jwt(access_token_claims),
        refresh_token: "refresh123",
        scope: "openid profile email offline_access"
      }
    end

    before do
      stub_request(:post, token_url).to_return(
        status: 200,
        body: token_response_body.to_json,
        headers: {"Content-Type" => "application/json"}
      )
    end

    def complete_callback(query = "")
      post "/auth/sps_commerce/callback#{query}",
           {"code" => "auth_code", "state" => "abc123"},
           "rack.session" => session
    end

    def auth_hash
      last_request.env["omniauth.auth"]
    end

    def token_request_body
      body = nil
      expect(WebMock).to have_requested(:post, token_url).with { |req| body = req.body; true }
      URI.decode_www_form(body).to_h
    end

    it "exchanges the code for a token with credentials in the body" do
      complete_callback

      expect(token_request_body).to include(
        "grant_type" => "authorization_code", "code" => "auth_code",
        "client_id" => "client_id", "client_secret" => "client_secret"
      )
    end

    it "does not fall back to HTTP basic auth for the client credentials" do
      complete_callback

      expect(WebMock).to have_requested(:post, token_url)
        .with { |req| !req.headers.key?("Authorization") }
    end

    it "sends a redirect_uri without query params" do
      complete_callback("?utm_source=sps")

      expect(token_request_body["redirect_uri"]).to eq("http://example.org/auth/sps_commerce/callback")
    end

    # OmniAuth's own callback_url drops SCRIPT_NAME, which would send the wrong
    # redirect_uri when the strategy is mounted under a prefix (e.g. Devise's /users).
    it "keeps the mount point in the redirect_uri" do
      post "/auth/sps_commerce/callback",
           {"code" => "auth_code", "state" => "abc123"},
           "rack.session" => session, "SCRIPT_NAME" => "/users"

      expect(token_request_body["redirect_uri"]).to eq("http://example.org/users/auth/sps_commerce/callback")
    end

    it "builds an auth hash carrying the token and refresh token" do
      complete_callback

      expect(auth_hash["credentials"]["token"]).to eq(token_response_body[:access_token])
      expect(auth_hash["credentials"]["refresh_token"]).to eq("refresh123")
      expect(auth_hash["credentials"]["expires"]).to be(true)
      expect(auth_hash["credentials"]["expires_at"]).to be_a(Integer)
    end

    it "exposes the access token's claims" do
      complete_callback

      expect(auth_hash["extra"]["access_token_claims"]).to eq(access_token_claims)
    end

    context "when the response carries an id_token" do
      let(:token_response_body) do
        super().merge(id_token: encode_jwt(
          "sub" => "auth0|id-sub", "name" => "Jane Doe",
          "email" => "jane@example.com", "nickname" => "jane"
        ))
      end

      it "takes uid and info from the id_token claims" do
        complete_callback

        expect(auth_hash["uid"]).to eq("auth0|id-sub")
        expect(auth_hash["info"]).to include("name" => "Jane Doe", "email" => "jane@example.com",
                                             "nickname" => "jane")
        expect(auth_hash["extra"]["claims"]).to include("sub" => "auth0|id-sub")
      end

      it "keeps the raw id_token out of extra params" do
        complete_callback

        expect(auth_hash["extra"]["params"]).not_to have_key("id_token")
      end
    end

    context "when the response carries only a JWT access token" do
      it "takes the uid from the access token claims" do
        complete_callback

        expect(auth_hash["uid"]).to eq("auth0|access-sub")
        expect(auth_hash["extra"]["claims"]).to eq(access_token_claims)
      end
    end

    context "when the access token is opaque" do
      let(:token_response_body) { super().merge(access_token: "opaque-token") }

      it "still authenticates, with no uid or claims" do
        complete_callback

        expect(last_request.env["omniauth.error"]).to be_nil
        expect(auth_hash["uid"]).to be_nil
        expect(auth_hash["extra"]["access_token_claims"]).to eq({})
      end
    end
  end

  describe "#callback_url" do
    context "when callback_url is configured" do
      let(:strategy_options) { {callback_url: "https://app.getdropstream.com/auth/sps_commerce/callback"} }

      it "uses the configured value verbatim" do
        expect(strategy.callback_url).to eq("https://app.getdropstream.com/auth/sps_commerce/callback")
      end
    end
  end
end
