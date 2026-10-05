# OmniAuth SPS Commerce

An OmniAuth strategy for [SPS Commerce](https://www.spscommerce.com). It runs the OAuth 2.0
authorization code flow against `auth.spscommerce.com` (SPS's Auth0 tenant) and returns an
access token and refresh token for the SPS APIs, such as the Transaction API.

Requires Ruby >= 3.2, OmniAuth 2.x and `omniauth-oauth2` 1.8 or 1.9.

## Installation

```ruby
gem 'omniauth-sps_commerce'
```

## Usage

OmniAuth 2 only accepts `POST` for the request phase. In a Rails app, add
[`omniauth-rails_csrf_protection`](https://github.com/cookpad/omniauth-rails_csrf_protection)
and link to the provider with `button_to`.

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :sps_commerce, ENV['SPS_CLIENT_ID'], ENV['SPS_CLIENT_SECRET']
end
```

Register the callback URL (`https://<host>/auth/sps_commerce/callback`) on the app in the
SPS Dev Center.

### Production and sandbox keys

Each SPS app comes with a production key and a sandbox key. Both authenticate against
`auth.spscommerce.com`, so register the strategy once per key under different names:

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :sps_commerce, ENV['SPS_CLIENT_ID'], ENV['SPS_CLIENT_SECRET']
  provider :sps_commerce, ENV['SPS_SANDBOX_CLIENT_ID'], ENV['SPS_SANDBOX_CLIENT_SECRET'],
           name: :sps_commerce_sandbox
end
```

The sandbox registration answers on `/auth/sps_commerce_sandbox` and
`/auth/sps_commerce_sandbox/callback`. A refresh token can only be redeemed with the key
that issued it, so record which registration a token came from (`auth.provider`).

Use a separate SPS app (and so separate keys) per deployment environment.

## The auth hash

```ruby
auth = request.env['omniauth.auth']
auth['provider']                    # "sps_commerce" or "sps_commerce_sandbox"
auth['uid']                         # Auth0 subject of the SPS user who authorized
auth['info']                        # name, email, nickname (from the id_token)
auth['credentials']['token']        # access token
auth['credentials']['refresh_token']
auth['credentials']['expires_at']
auth['extra']['claims']             # id_token claims
auth['extra']['access_token_claims']# access token claims, including SPS-specific ones
```

Token claims are decoded without verifying signatures. That is safe only because tokens
come straight from `auth.spscommerce.com` over TLS, never from the browser. Don't reuse the
decoder on tokens from any other source.

## Configuring

| Option | Default | Notes |
|--------|---------|-------|
| `scope` | `openid profile email offline_access` | `offline_access` is what returns a refresh token. |
| `audience` | `https://spscommerce.com` | Without an audience, Auth0 issues an opaque token that only works on `/userinfo`. |
| `client_options[:site]` | `https://auth.spscommerce.com` | |
| `callback_url` | derived from the request | Drops the callback's query string, since Auth0 requires an exact `redirect_uri` match. |

`prompt` and `login_hint` can also be set per request (`/auth/sps_commerce?login_hint=…`).
Nothing else is taken from request params.

The endpoints come from
[SPS's OpenID configuration](https://auth.spscommerce.com/.well-known/openid-configuration).

## Development

Run `bin/setup`, then `bundle exec rake spec`. Run `bundle exec bundle-audit check --update`
to check the locked dependencies against the advisory database; CI runs it weekly.

## Releasing

Releases are cut from the GitHub Releases UI and published by the `Release` workflow
through [RubyGems trusted publishing](https://guides.rubygems.org/trusted-publishing/):

1. Bump `VERSION` in `lib/omniauth-sps_commerce/version.rb` and add a `CHANGELOG.md`
   section. Commit both on `main`.
2. Draft a release targeting `main` with tag `vX.Y.Z` matching `version.rb`, then publish.

One-time setup on rubygems.org: open the gem, then **Trusted publishers** → **Create**, with
owner `dropstream`, repository `omniauth-sps_commerce`, workflow `release.yml` and environment
`release`. The repo also needs an environment named `release`.

## License

Available as open source under the terms of the [MIT License](LICENSE.txt).
