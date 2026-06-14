# Manual integration test fixture: seeds a talk with two finished sessions
# and reactions, for scripts/manual_tests/session_analytics.sh.
# See docs/manual_tests.md.
#
# Usage: mix run scripts/manual_tests/seed_sessions.exs <email>
#
# Prints email=, talk_id=, session1_id=, session2_id= on stdout.

alias Speechwave.{Accounts, Talks, Reactions}
alias Speechwave.Accounts.Scope

[email | _] = System.argv()

{:ok, user} = Accounts.register_or_get_user_by_email(email)
scope = Scope.for_user(user)

title = "manual-test-#{System.system_time(:second)}"
slug = Talks.generate_slug(title)
{:ok, talk} = Talks.create_talk(scope, %{title: title, slug: slug})

{:ok, session1} = Talks.start_session(talk)
Reactions.create_reaction(session1, "🔥", 1)
Reactions.create_reaction(session1, "❤️", 1)
Reactions.create_reaction(session1, "🎉", 2)
{:ok, session1} = Talks.stop_session(session1)

{:ok, session2} = Talks.start_session(talk)
Reactions.create_reaction(session2, "🔥", 1)
Reactions.create_reaction(session2, "👏", 2)
{:ok, session2} = Talks.stop_session(session2)

IO.puts("email=#{email}")
IO.puts("talk_id=#{talk.id}")
IO.puts("session1_id=#{session1.id}")
IO.puts("session2_id=#{session2.id}")
