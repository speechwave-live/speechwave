# Routes

- `GET` `/` [auth] ✓
- `GET` `/health` [auth] ✓
- `GET` `/terms` [auth] ✓
- `GET` `/privacy` [auth] ✓
- `DELETE` `/users/account` [auth] ✓
- `GET` `/users/settings/export` [auth] ✓
- `GET` `/consent-export` [auth]
- `GET` `/users/magic_link/:token` params(token) [auth]
- `DELETE` `/users/log-out` [auth] ✓
- `GET` `/:provider` params(provider) [auth]
- `GET` `/:provider/callback` params(provider) [auth]
- `GET` `/login` [auth]
- `POST` `/login` [auth]
