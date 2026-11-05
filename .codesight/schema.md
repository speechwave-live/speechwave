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
