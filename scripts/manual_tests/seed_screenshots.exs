# Screenshot fixture: creates a talk with slug "emojilove", seeds one finished
# session with rich per-slide reactions (for analytics screenshot), and starts
# a second active session (for the extension connection screenshot).
#
# Usage: mix run scripts/manual_tests/seed_screenshots.exs <email>

alias Speechwave.{Accounts, Talks, Reactions}
alias Speechwave.Accounts.Scope

[email | _] = System.argv()

{:ok, user} = Accounts.register_or_get_user_by_email(email)
scope = Scope.for_user(user)

# Delete existing emojilove talk if present so this script is re-runnable
case Talks.get_talk_by_slug("emojilove") do
  nil -> :ok
  existing -> Talks.delete_talk(existing)
end

{:ok, talk} = Talks.create_talk(scope, %{title: "Emoji Love", slug: "emojilove"})

# Finished session with rich per-slide reactions
{:ok, session1} = Talks.start_session(talk)

Reactions.create_reaction(session1, "❤️", 1)
Reactions.create_reaction(session1, "❤️", 1)
Reactions.create_reaction(session1, "❤️", 1)
Reactions.create_reaction(session1, "👏", 1)
Reactions.create_reaction(session1, "👏", 1)
Reactions.create_reaction(session1, "🎉", 1)

Reactions.create_reaction(session1, "🤯", 2)
Reactions.create_reaction(session1, "🤯", 2)
Reactions.create_reaction(session1, "🤯", 2)
Reactions.create_reaction(session1, "🤯", 2)
Reactions.create_reaction(session1, "😮", 2)
Reactions.create_reaction(session1, "😮", 2)
Reactions.create_reaction(session1, "❤️", 2)

Reactions.create_reaction(session1, "👏", 3)
Reactions.create_reaction(session1, "👏", 3)
Reactions.create_reaction(session1, "👏", 3)
Reactions.create_reaction(session1, "👏", 3)
Reactions.create_reaction(session1, "👏", 3)
Reactions.create_reaction(session1, "❤️", 3)
Reactions.create_reaction(session1, "❤️", 3)
Reactions.create_reaction(session1, "🎉", 3)

Reactions.create_reaction(session1, "🎉", 4)
Reactions.create_reaction(session1, "🎉", 4)
Reactions.create_reaction(session1, "🎉", 4)
Reactions.create_reaction(session1, "😂", 4)
Reactions.create_reaction(session1, "😂", 4)
Reactions.create_reaction(session1, "❤️", 4)

{:ok, session1} = Talks.stop_session(session1)

# Active session — connect the extension to this
{:ok, session2} = Talks.start_session(talk)

IO.puts("talk_slug=emojilove")
IO.puts("session1_id=#{session1.id}  (finished, has analytics)")
IO.puts("session2_id=#{session2.id}  (active — connect extension to this)")
IO.puts("")
IO.puts("Extension: connect to slug \"emojilove\"")
IO.puts("Analytics: http://localhost:4000  -> Dashboard -> Emoji Love")
