# Database

> **Navigation aid.** Schema shapes and field types extracted via AST. Read the actual schema source files before writing migrations or query logic.

**ecto** — 7 models

### User

- `email`: string
- `authenticated_at`: timestamp
- `api_key`: string
- `plan`: enum
- `is_admin`: boolean
- `confirmed_at`: timestamp
- `welcomed_at`: timestamp
- `overlay_size_percent`: integer
- `fireworks_enabled`: boolean
- `customize_overlay_size`: boolean
- _relations_: identities: has_many(Speechwave.Accounts.UserIdentity)

### UserConsent

fk: user_id

- `consent_type`: string
- `granted`: boolean
- `granted_at`: timestamp
- `source`: string
- `revoked_at`: timestamp
- `user_id`: integer _(fk)_
- _relations_: user: belongs_to(User)

### UserIdentity

fk: user_id

- `provider`: string
- `uid`: string
- `user_id`: integer _(fk)_
- _relations_: user: belongs_to(Speechwave.Accounts.User)

### UserToken

fk: user_id

- `token`: bytes
- `context`: string
- `sent_to`: string
- `authenticated_at`: timestamp
- `user_id`: integer _(fk)_
- _relations_: user: belongs_to(Speechwave.Accounts.User)

### Reaction

fk: audience_id, talk_session_id

- `emoji`: string
- `slide_number`: integer
- `audience_id`: string _(fk)_
- `talk_session_id`: integer _(fk)_
- _relations_: talk_session: belongs_to(Speechwave.Talks.TalkSession)

### Talk

fk: user_id

- `title`: string
- `slug`: string
- `user_id`: integer _(fk)_
- _relations_: user: belongs_to(Speechwave.Accounts.User), talk_sessions: has_many(Speechwave.Talks.TalkSession)

### TalkSession

fk: talk_id

- `label`: string
- `started_at`: timestamp
- `ended_at`: timestamp
- `talk_id`: integer _(fk)_
- _relations_: talk: belongs_to(Speechwave.Talks.Talk), reactions: has_many(Speechwave.Reactions.Reaction)

## Schema Source Files

Search for ORM schema declarations:
- Drizzle: `pgTable` / `mysqlTable` / `sqliteTable`
- Prisma: `prisma/schema.prisma`
- TypeORM: `@Entity()` decorator
- SQLAlchemy: class inheriting `Base`

---
_Back to [overview.md](./overview.md)_