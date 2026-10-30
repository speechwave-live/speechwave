# Auth

> **Navigation aid.** Route list and file locations extracted via AST. Read the source files listed below before implementing or modifying this subsystem.

The Auth subsystem handles **2 routes** and touches: auth.

## Routes

- `GET` `/login` [auth]
  `lib/speechwave_web/router.ex`
- `POST` `/login` [auth]
  `lib/speechwave_web/router.ex`

## Middleware

- **auth_throttle** (auth) — `lib/speechwave/auth_throttle.ex`
- **rate_limiter** (auth) — `lib/speechwave/rate_limiter.ex`
- **auth_throttle_test** (auth) — `test/e2e/auth_throttle_test.exs`
- **auth_throttle_test** (auth) — `test/speechwave/auth_throttle_test.exs`
- **rate_limiter_test** (auth) — `test/speechwave/rate_limiter_test.exs`

## Source Files

Read these before implementing or modifying this subsystem:
- `lib/speechwave_web/router.ex`

---
_Back to [overview.md](./overview.md)_