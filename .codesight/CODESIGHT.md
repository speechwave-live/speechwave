# speechwave — AI Context Map

> **Stack:** phoenix | ecto | unknown | elixir
> **Monorepo:** assets, speechwave-load-test

> 13 routes (3 inferred) + 3 ws | 7 models | 0 components | 1 lib files | 9 env vars | 6 middleware | 4 events | 75% test coverage
> **Token savings:** this file is ~2,500 tokens. Without it, AI exploration would cost ~22,900 tokens. **Saves ~20,400 tokens per conversation.**
> **Last scanned:** 2026-11-19 23:50 — re-run after significant changes

---

# Routes

- `GET` `/` [auth] ✓
- `GET` `/health` [auth] ✓
- `GET` `/terms` [auth] ✓
- `GET` `/privacy` [auth] ✓
- `DELETE` `/users/account` [auth] ✓
- `POST` `/users/settings/export` [auth] ✓
- `GET` `/consent-export` [auth]
- `GET` `/users/magic_link/:token` params(token) [auth]
- `DELETE` `/users/log-out` [auth] ✓
- `GET` `/:provider` params(provider) [auth]
- `GET` `/:provider/callback` params(provider) [auth]
- `GET` `/login` [auth]
- `POST` `/login` [auth]

## WebSocket Events

- `WS` `open` — `scripts/load_test/audience_load.mjs`
- `WS` `error` — `scripts/load_test/audience_load.mjs`
- `WS` `message` — `scripts/load_test/audience_load.mjs`

---

# Schema

### User
- email: string
- authenticated_at: timestamp
- api_key: string
- plan: enum
- is_admin: boolean
- confirmed_at: timestamp
- welcomed_at: timestamp
- overlay_size_percent: integer
- fireworks_enabled: boolean
- customize_overlay_size: boolean
- _relations_: identities: has_many(Speechwave.Accounts.UserIdentity)

### UserConsent
- consent_type: string
- granted: boolean
- granted_at: timestamp
- source: string
- revoked_at: timestamp
- user_id: integer (fk)
- _relations_: user: belongs_to(User)

### UserIdentity
- provider: string
- uid: string
- user_id: integer (fk)
- _relations_: user: belongs_to(Speechwave.Accounts.User)

### UserToken
- token: bytes
- context: string
- sent_to: string
- authenticated_at: timestamp
- user_id: integer (fk)
- _relations_: user: belongs_to(Speechwave.Accounts.User)

### Reaction
- emoji: string
- slide_number: integer
- audience_id: string (fk)
- talk_session_id: integer (fk)
- _relations_: talk_session: belongs_to(Speechwave.Talks.TalkSession)

### Talk
- title: string
- slug: string
- user_id: integer (fk)
- _relations_: user: belongs_to(Speechwave.Accounts.User), talk_sessions: has_many(Speechwave.Talks.TalkSession)

### TalkSession
- label: string
- started_at: timestamp
- ended_at: timestamp
- participant_limit_hit_at: timestamp
- talk_id: integer (fk)
- _relations_: talk: belongs_to(Speechwave.Talks.Talk), reactions: has_many(Speechwave.Reactions.Reaction)

---

# Libraries

- `assets/js/audience_id.js` — function audienceId: (talkSlug) => void

---

# Config

## Environment Variables

- `ADMIN_PASSWORD` (has default) — .env
- `GITHUB_CLIENT_ID` (has default) — .env
- `GITHUB_CLIENT_SECRET` (has default) — .env
- `GOOGLE_CLIENT_ID` (has default) — .env
- `GOOGLE_CLIENT_SECRET` (has default) — .env
- `MICROSOFT_CLIENT_ID` (has default) — .env
- `MICROSOFT_CLIENT_SECRET` (has default) — .env
- `MICROSOFT_TENANT_ID` (has default) — .env
- `NODE_ENV` **required** — assets/js/app.js

## Config Files

- `Dockerfile`
- `fly.toml`

---

# Middleware

## custom
- fly_db_migrate — `docs/fly_db_migrate.md`

## auth
- auth_throttle — `lib/speechwave/auth_throttle.ex`
- rate_limiter — `lib/speechwave/rate_limiter.ex`
- auth_throttle_test — `test/e2e/auth_throttle_test.exs`
- auth_throttle_test — `test/speechwave/auth_throttle_test.exs`
- rate_limiter_test — `test/speechwave/rate_limiter_test.exs`

---

# Dependency Graph

## Most Imported Files (change these carefully)

- `lib/speechwave/accounts_fixtures.ex` — imported by **29** files
- `lib/speechwave_web/conn_case.ex` — imported by **23** files
- `lib/speechwave/accounts.ex` — imported by **22** files
- `lib/speechwave/talks_fixtures.ex` — imported by **16** files
- `lib/speechwave/repo.ex` — imported by **15** files
- `lib/speechwave/data_case.ex` — imported by **14** files
- `lib/speechwave/accounts/scope.ex` — imported by **12** files
- `lib/ex_unit/case.ex` — imported by **12** files
- `lib/speechwave_web/e2_e_case.ex` — imported by **10** files
- `lib/speechwave/deletion_log.ex` — imported by **9** files
- `lib/speechwave/.ex` — imported by **9** files
- `lib/speechwave/accounts/user.ex` — imported by **7** files
- `lib/speechwave/talks.ex` — imported by **6** files
- `lib/speechwave/plans.ex` — imported by **6** files
- `lib/speechwave/accounts/.ex` — imported by **5** files
- `lib/speechwave_web/user_auth.ex` — imported by **5** files
- `lib/speechwave/talks/talk.ex` — imported by **4** files
- `lib/speechwave/talks/.ex` — imported by **3** files
- `lib/speechwave/reactions/reaction.ex` — imported by **3** files
- `lib/speechwave/talks/talk_session.ex` — imported by **3** files

## Import Map (who imports what)

- `lib/speechwave/accounts_fixtures.ex` ← `test/speechwave/accounts/suspicious_user_reaper_test.exs`, `test/speechwave/accounts_delete_test.exs`, `test/speechwave/accounts_test.exs`, `test/speechwave/admin/consent_export_test.exs`, `test/speechwave/admin/stats_test.exs` +24 more
- `lib/speechwave_web/conn_case.ex` ← `test/speechwave_web/components/layouts_test.exs`, `test/speechwave_web/controllers/admin/consent_export_controller_test.exs`, `test/speechwave_web/controllers/error_html_test.exs`, `test/speechwave_web/controllers/error_json_test.exs`, `test/speechwave_web/controllers/page_controller_test.exs` +18 more
- `lib/speechwave/accounts.ex` ← `lib/speechwave/accounts/suspicious_user_reaper.ex`, `lib/speechwave/data_export.ex`, `lib/speechwave_web/channels/reaction_channel.ex`, `lib/speechwave_web/controllers/dev_login_controller.ex`, `lib/speechwave_web/controllers/user_account_controller.ex` +17 more
- `lib/speechwave/talks_fixtures.ex` ← `test/e2e/audience_reconnect_test.exs`, `test/e2e/reaction_flow_test.exs`, `test/e2e/session_analytics_test.exs`, `test/speechwave/accounts_delete_test.exs`, `test/speechwave/admin/consent_export_test.exs` +11 more
- `lib/speechwave/repo.ex` ← `lib/speechwave/accounts.ex`, `lib/speechwave/admin/consent_export.ex`, `lib/speechwave/admin/stats.ex`, `lib/speechwave/data_export.ex`, `lib/speechwave/reactions.ex` +10 more
- `lib/speechwave/data_case.ex` ← `test/speechwave/accounts/suspicious_user_reaper_test.exs`, `test/speechwave/accounts_delete_test.exs`, `test/speechwave/accounts_test.exs`, `test/speechwave/admin/consent_export_test.exs`, `test/speechwave/admin/stats_test.exs` +9 more
- `lib/speechwave/accounts/scope.ex` ← `lib/speechwave/data_export.ex`, `lib/speechwave/talks.ex`, `lib/speechwave_web/user_auth.ex`, `scripts/manual_tests/seed_screenshots.exs`, `test/speechwave/data_export_test.exs` +7 more
- `lib/ex_unit/case.ex` ← `test/speechwave/admin/chart_test.exs`, `test/speechwave/admin/csv_test.exs`, `test/speechwave/audience_slots_test.exs`, `test/speechwave/auth_throttle_test.exs`, `test/speechwave/data_export_throttle_test.exs` +7 more
- `lib/speechwave_web/e2_e_case.ex` ← `test/e2e/account_settings_test.exs`, `test/e2e/audience_reconnect_test.exs`, `test/e2e/auth_throttle_test.exs`, `test/e2e/dashboard_test.exs`, `test/e2e/email_consent_test.exs` +5 more
- `lib/speechwave/deletion_log.ex` ← `lib/speechwave/accounts.ex`, `lib/speechwave/admin/stats.ex`, `lib/speechwave/db_backup.ex`, `test/speechwave/accounts/suspicious_user_reaper_test.exs`, `test/speechwave/accounts_delete_test.exs` +4 more

---

# Events & Queues

- `reactions:#{talk.slug}` [channel] — `lib/speechwave_web/live/talk_live.ex`
- `slides:#{talk.slug}` [channel] — `lib/speechwave_web/live/talk_live.ex`
- `presenters:#{user.id}` [channel] — `test/speechwave_web/channels/reaction_channel_test.exs`
- `user:#{user.id}:disconnect` [channel] — `test/speechwave_web/live/user_live/settings_test.exs`

---

# Test Coverage

> **75%** of routes and models are covered by tests
> 61 test files found

## Covered Routes

- GET:/
- GET:/health
- GET:/terms
- GET:/privacy
- DELETE:/users/account
- POST:/users/settings/export
- DELETE:/users/log-out
- WS:error

## Covered Models

- User
- UserConsent
- UserIdentity
- UserToken
- Reaction
- Talk
- TalkSession

---

# Git Hooks

> **Note for agents:** These hooks fire automatically on git operations and will block the operation if they fail.

## `pre-commit` — raw git hook

- **npx**: `npx codesight --wiki -o .codesight`
- **git**: `git add .codesight/`

## `pre-push` — raw git hook

- **echo**: `echo "Running Credo to check for code consistency..."`
- **mix**: `mix credo --strict --all`
- **CREDO_EXIT_CODE=$?**: `CREDO_EXIT_CODE=$?`
- **if**: `if [ $CREDO_EXIT_CODE -ne 0 ]; then`
- **echo**: `echo "Credo found issues."`
- **echo**: `echo "Run `credo --strict --all --format json` for details."`
- **echo**: `echo "Please fix them before pushing!"`
- **exit**: `exit 1`
- **fi**: `fi`
- **echo**: `echo "No issues found by Credo. Proceeding with push."`
- **exit**: `exit 0`

_Source: .git/hooks/pre-commit, .git/hooks/pre-push_

---

_Generated by [codesight](https://github.com/Houseofmvps/codesight) — see your codebase clearly_