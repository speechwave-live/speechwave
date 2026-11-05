# Router.ex

> **Navigation aid.** Route list and file locations extracted via AST. Read the source files listed below before implementing or modifying this subsystem.

The Router.ex subsystem handles **9 routes** and touches: auth.

## Routes

- `GET` `/terms` [auth]
  `lib/speechwave_web/router.ex`
- `GET` `/privacy` [auth]
  `lib/speechwave_web/router.ex`
- `DELETE` `/users/account` [auth]
  `lib/speechwave_web/router.ex`
- `POST` `/users/settings/export` [auth]
  `lib/speechwave_web/router.ex`
- `GET` `/consent-export` [auth]
  `lib/speechwave_web/router.ex`
- `GET` `/users/magic_link/:token` params(token) [auth]
  `lib/speechwave_web/router.ex`
- `DELETE` `/users/log-out` [auth]
  `lib/speechwave_web/router.ex`
- `GET` `/:provider` params(provider) [auth]
  `lib/speechwave_web/router.ex`
- `GET` `/:provider/callback` params(provider) [auth]
  `lib/speechwave_web/router.ex`

## Source Files

Read these before implementing or modifying this subsystem:
- `lib/speechwave_web/router.ex`

---
_Back to [overview.md](./overview.md)_