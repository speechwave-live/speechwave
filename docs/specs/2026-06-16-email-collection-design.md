# Email Collection Design

**Date:** 2026-06-16
**Status:** Approved

## Overview

Add GDPR-compliant marketing consent collection to cover three surfaces: the magic link login screen (which also serves as registration), the "Notify me" modal on the pricing page, and an export UI in the planned super admin section. Consent, once granted, can only be revoked explicitly — never implicitly via a subsequent login.

---

## Data Model

One migration adds three columns to `users`:

| Column | Type | Default | Notes |
|---|---|---|---|
| `marketing_consent` | `boolean` | `false` | Whether the user has opted in |
| `marketing_consent_at` | `utc_datetime` | `nil` | When consent was last granted — GDPR audit trail |
| `notify_interest` | `string` | `nil` | Source/segment: `"pro"`, `"enterprise"`, or `"login"` |

`notify_interest` is a **segmentation tag**, not a permission scope. All consented users share the same permission level (general product updates). The value tells you how they arrived: via the Pro card, the Enterprise card, or the login screen directly.

A new `marketing_changeset/2` on `User` handles updates to these three fields, separate from the existing `email_changeset` and `plan_changeset`.

---

## Login Screen Consent (Magic Link + SSO)

### Checkbox placement and copy

An unchecked opt-in checkbox is added to the login form between the email input and the "Send sign-in link" button. It appears above the SSO divider, so it's visible regardless of which auth method the user chooses.

**Label copy:**
> Keep me updated on new features and product announcements (no spam, no selling your email)

Unchecked by default. Not required. Applies to both magic link and SSO flows.

### Magic link passthrough

Consent cannot be stored in the Phoenix session because the user may open the magic link in a different browser or device. Instead, consent is encoded in the magic link URL:

- Checkbox checked → magic link URL includes `?updates=true`
- Checkbox unchecked → no param added

`UserSessionController.magic_link/2` reads the param on callback and applies consent after a successful login.

### SSO passthrough

OAuth callbacks always happen in the same browser. Consent is stored in the Phoenix session (alongside the existing `oauth_context` key) before the OAuth redirect and applied in `handle_oauth_login/3` on callback.

### Server-side consent rule

The checkbox can only **grant** consent, never revoke it. The rule applied on every callback:

| `marketing_consent` (current) | `?updates=true` present | Action |
|---|---|---|
| `false` | yes | Set `true`, record timestamp, set `notify_interest: "login"` |
| `true` | yes | No change (already consented) |
| `false` | no | No change |
| `true` | no | **No change** — not checking the box on re-login does not revoke consent |

Revocation is an explicit user action in account settings only (see below).

---

## "Notify Me" Modal (Pricing Page)

### Trigger behaviour

The "Notify me" button on the Pro card and the "Contact us" button on the Enterprise card (both currently disabled stubs) trigger the same behaviour depending on auth state. The Enterprise button label may be updated to "Notify me" for consistency, or kept as "Contact us" — either works with this flow.

- **Logged-out user** → opens a modal with an email input
- **Logged-in user without consent** → no modal; applies consent immediately and shows a flash: *"You're on the list! We'll keep you posted."*
- **Logged-in user already consented** → no modal; shows flash: *"You're already on the list!"*

### Modal copy

> **Get notified when Pro launches**
> We'll let you know the moment it's ready — and keep you in the loop on product updates. No spam, no selling your email.
> [email input]
> [Notify me →]

### Flow

On modal submit, the email goes through the existing magic link flow with two extra params:

```
/users/magic_link/<token>?updates=true&notify=pro
```

On callback, in addition to the standard consent rule above:
- `notify_interest` is set to `"pro"` (or `"enterprise"`) if not already set, or updated if the incoming value differs

The user lands on the app dashboard (created or logged in) with a flash message:
> "You're on the list! We'll email you when Pro launches."

### Consent copy alignment

The modal copy deliberately matches the broader scope of the login screen checkbox — general product updates, not just the Pro launch. `notify_interest` captures that they arrived via the Pro card, but the underlying permission is the same for all consented users.

---

## Account Settings — Revocation

A dedicated "Email preferences" row in account settings shows the current consent state and lets users opt out. This is the **only** revocation path. Unsetting `marketing_consent` also clears `marketing_consent_at` and `notify_interest`.

If a right-to-be-forgotten request is ever needed, account deletion handles it via standard cascade.

---

## Super Admin Export

In the planned super admin section of the user dashboard (behind the existing `is_admin` guard), add an email export form:

- Checkboxes to filter by `notify_interest`: `pro`, `enterprise`, `login`, or all consented users
- A "Download CSV" button that streams `email, notify_interest, marketing_consent_at, inserted_at`

No mix task. This runs in production without SSH access and is self-service for non-engineers.

Until the admin section is built, engineers can query the production console directly via IEx.

---

## Out of Scope

- Email marketing platform integration (Mailchimp, ConvertKit, etc.) — decided later
- Granular per-topic subscription preferences
- Double opt-in confirmation emails
- Unsubscribe links in emails (handled by the marketing platform when chosen)
