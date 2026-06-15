# Manual integration test fixture: seeds a talk with one active (unstopped)
# session and no reactions, for scripts/manual_tests/reaction_flow.sh.
# See docs/manual_tests.md.
#
# Usage: mix run scripts/manual_tests/seed_active_session.exs <email>
#
# Prints email=, talk_id=, talk_slug=, session_id= on stdout.

alias Speechwave.{Accounts, Talks}
alias Speechwave.Accounts.Scope

[email | _] = System.argv()

{:ok, user} = Accounts.register_or_get_user_by_email(email)
scope = Scope.for_user(user)

title = "manual-test-#{System.system_time(:second)}"
slug = Talks.generate_slug(title)
{:ok, talk} = Talks.create_talk(scope, %{title: title, slug: slug})

{:ok, session} = Talks.start_session(talk)

IO.puts("email=#{email}")
IO.puts("talk_id=#{talk.id}")
IO.puts("talk_slug=#{talk.slug}")
IO.puts("session_id=#{session.id}")
