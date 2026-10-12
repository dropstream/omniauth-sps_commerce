# Changelog

All notable changes to this project are documented in this file.

## [0.1.0] - 2026-10-12

### Added

- `OmniAuth::Strategies::SpsCommerce`, registered as `:sps_commerce`: the authorization code
  flow against `auth.spscommerce.com` (`/authorize`, `/oauth/token`), with a JSON token
  request carrying the client credentials in its body.
- Default scope `openid profile email offline_access` and default audience
  `https://spscommerce.com`, so the callback returns an API access token and a refresh token.
- `uid` and `info` from the id_token, falling back to the access token's claims; `extra`
  carries both claim sets and the token response params (without the raw id_token).
- Per-request `prompt` and `login_hint`.
- A `callback_url` override that drops the callback's query string and honors a configured
  `:callback_url`.
- Supports `omniauth-oauth2` 1.8 as well as 1.9, so apps still on 1.8 can use it.

[0.1.0]: https://github.com/dropstream/omniauth-sps_commerce/releases/tag/v0.1.0
