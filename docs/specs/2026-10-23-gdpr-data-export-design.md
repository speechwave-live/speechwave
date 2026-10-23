# Download my data (GDPR access and portability)

## Why

GDPR Articles 15 (access) and 20 (portability) give people a right to a copy
of the personal data held about them, in a structured, commonly used,
machine-readable format. Today that is a manual request to
admin@speechwave.live. Tracy wants it self-service in Settings, next to the
self-service account deletion (`docs/specs/2026-10-15-account-deletion-design.md`).

The main use is archiving: "in case I want it later". The likely reader is an
LLM the user hands the file to, so the export must be self-explanatory with no
outside context.

## What it does

A "Download my data" button in the Settings page, beside account deletion.
Pressing it downloads `speechwave-data.zip` containing three files:

- `speechwave_data.json`: the data.
- `speechwave_data.schema.json`: a JSON Schema describing that file.
- `README.md`: plain-language explanation for an LLM or a person opening the
  zip cold.

The zip is built on request and sent straight back. Nothing is stored and
nothing is emailed. Only the signed-in user can download their own data. No
extra re-authentication (read-only, unlike deletion). This is a decision of the
author of this spec, not of Tracy's.

### Contents of `speechwave_data.json`

Top level carries `exported_at` (UTC ISO 8601) and a `format_version`.

- **account**: email, plan, `is_admin`, `confirmed_at`, `welcomed_at`,
  `overlay_size_percent`, `fireworks_enabled`, `inserted_at`, `updated_at`.
- **sign_in_providers**: provider, provider UID, linked date. (Provider UIDs
  are included: they are identifiers about the user and not secrets.)
- **consents**: consent type, granted, `granted_at`, `revoked_at`, source.
- **talks**: title, slug, `inserted_at`, `updated_at`. Each talk has **sessions** (label,
  `started_at`, `ended_at`), and each session has **reactions** as aggregates
  only: count per emoji, count per slide number (and emoji within it), total,
  and distinct audience size. Audience size is per session and
  counts distinct non-null `audience_id` values, the same as the dashboard's
  `Reactions.count_audience/1`; null IDs are ignored. (Decided by the spec
  author.)

### Deliberately excluded (and stated in the README)

| Excluded | Reason given |
|---|---|
| API key | A credential. Exporting it would let anyone holding the zip act as the user. It is visible and regenerable in Settings. |
| Session and login tokens (`users_tokens`) | Credentials, same reason. |
| Individual reactions, their timestamps, audience IDs | They describe audience members, not the account holder (GDPR Art. 15(4): access must not harm others' rights). Audience IDs are pseudonymous browser identifiers that cannot be linked to the requester. Counts are provided instead. |
| Backups | Copies held in backups are not included in the export. |

### README requirements

Written for an LLM reader. It must:

- say what Speechwave is and describe each section and field of the JSON;
- state the export date and that the data is a snapshot;
- state that this is **not a backup and cannot be re-imported** into
  Speechwave at this time;
- list what is excluded, with the reasons above;
- link to the privacy policy for purposes, recipients, retention and rights
  (Art. 15 requires this information alongside the data), and give
  admin@speechwave.live for questions.

README and privacy page text is user-facing: use the `writing-tracy` skill and
the writing style rules (no AI cliches, no dash-separated phrases).

### Rate limiting

One download per user every few minutes (exact cooldown left to the builder,
suggest 5 minutes), enforced in memory in the style of
`Speechwave.AuthThrottle` (ETS, fail open on restart, log a warning when
limited). Keyed by user id. When limited the user sees a "try again in N
minutes" message and no file is sent. The button is a plain link to a
controller route (e.g. `GET /users/settings/export`); when limited, the
controller redirects back to Settings with an error flash. The check and the
cooldown record are one atomic ETS operation, and the cooldown is recorded when
the build succeeds, so a failed build does not lock the user out. (Decided by
the spec author.)

### Privacy page

`/privacy` currently directs access requests to the admin email. Update it to
describe the self-service export (what it contains, where the button is), and
keep admin@speechwave.live as the fallback and for anything the export does
not cover.

## Goals

- GDPR-compliant access and portability for every field we hold about the user
  except credentials.
- Output an LLM can consume without help.

## Non-goals and anti-goals

- No re-import or backup function.
- No raw reaction rows, no admin-side export of another user's data.
- No stored or emailed exports, no background jobs.
- Anti-goal: leaking any secret, or any other person's identifier, in the zip.

## Constraints

- Use Erlang's built-in `:zip` (in memory) and the already-present `Jason`. The
  only new dependency is `ex_json_schema`, added with `only: :test` (decided
  with Tracy).
- The JSON Schema is hand-maintained or generated; a test must validate the
  produced JSON against the schema with `ex_json_schema` so the two cannot
  drift. The schema can be strict (`additionalProperties: false`,
  `format: date-time`) as far as the validator supports it.
- Route and button live in the authenticated scope, under the user's own
  `current_scope`; the context function takes `current_scope` as first
  argument and queries only that user's rows.

## Left to the builder

Module and function names (a context function that builds the export map plus
a thin controller action are expected, since a LiveView cannot send a file
download directly), the exact cooldown, JSON key naming details, the wording of
the README and privacy text within the requirements above, and test layout.
