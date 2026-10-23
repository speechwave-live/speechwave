# Your Speechwave data

This zip is a copy of the personal data Speechwave holds about your account. It was made on {{exported_at}} (UTC) and is a snapshot of your data at that moment.

Speechwave (https://speechwave.live) lets an audience send emoji reactions to a live talk. A speaker creates talks, runs sessions of a talk, and sees the reactions come in.

## What is in this zip

- `speechwave_data.json`: your data.
- `speechwave_data.schema.json`: a JSON Schema describing every field in the data file, with a description for each one.
- `README.md`: this file.

If you give these files to an AI assistant, give it all three.

## What the data file contains

- `account`: your email address, plan, settings and key dates. `is_admin` is true only for Speechwave administrator accounts.
- `sign_in_providers`: the Google, Microsoft or GitHub sign-ins linked to your account, with the identifier each provider uses for you.
- `consents`: your consent records, for example marketing email, with when you gave or withdrew consent and where you gave it.
- `talks`: your talks. Each talk has its `sessions`, and each session has a summary of the `reactions` it received: the total, how many different audience members reacted, and counts by emoji and by slide.

Dates are in UTC, written as ISO 8601 (for example `2026-10-23T12:00:00Z`).

## What is not included, and why

- **Your API key and login tokens.** These are credentials. Anyone holding this file could use them to act as you, and a download is easy to forget about. Your API key is shown in Settings, where you can replace it.
- **Individual reactions, their times and audience IDs.** Reactions come from audience members, not from you, so they are other people's data. Each audience member is only a random browser identifier that cannot be linked back to you. You get the counts instead.
- **Copies in backups.** Speechwave keeps backups for a limited time, and this export does not cover them. Backup copies are removed on the schedule in the privacy policy.

## This is not a backup

This file is a copy of your data for you to read and keep. It is not a backup of your account, and Speechwave cannot re-import it at this time. Deleting your account removes your data for good, so keep this file somewhere safe if you want a record.

## Questions

The privacy policy at https://speechwave.live/privacy explains what we collect and why, and how deletion and backups work. For anything else, email admin@speechwave.live.
