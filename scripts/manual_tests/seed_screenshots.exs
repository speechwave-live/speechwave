# Screenshot fixture: creates a talk with slug "emojilove", seeds one finished
# session with timed reactions across six slides (for the analytics
# screenshot), and starts
# a second active session (for the extension connection screenshot).
#
# Usage: mix run scripts/manual_tests/seed_screenshots.exs <email>

alias Speechwave.{Accounts, Talks}
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

# Finished session: a 26 minute talk with reactions spread over time, so the
# analytics page can show its timeline, people counts and slide labels.
# Fixed random seed, so every run draws the same chart.
:rand.seed(:exsss, {7, 21, 42})

{:ok, session1} = Talks.start_session(talk)

started_at = DateTime.utc_now() |> DateTime.add(-3 * 3600, :second) |> DateTime.truncate(:second)
ended_at = DateTime.add(started_at, 26 * 60, :second)

session1 =
  session1
  |> Ecto.Changeset.change(started_at: started_at, ended_at: ended_at)
  |> Speechwave.Repo.update!()

# Fourteen audience members. Only a one-way hash is ever stored, as in the app.
audience =
  for i <- 1..14,
      do: :crypto.hash(:sha256, "screenshot-audience-#{i}") |> Base.encode16(case: :lower)

# {slide, seconds into the talk when its first reaction arrives, reaction
# count, how many audience members react, emoji weights}
slides = [
  {1, 45, 14, 6, ["❤️", "❤️", "❤️", "👏", "👏", "🎉"]},
  {2, 250, 22, 9, ["🤯", "🤯", "🤯", "🤯", "😮", "😮", "❤️"]},
  {3, 510, 18, 8, ["👏", "👏", "👏", "👏", "👏", "❤️", "❤️", "🎉"]},
  {4, 800, 41, 13, ["🎉", "🎉", "🎉", "🔥", "🔥", "😂", "😂", "❤️"]},
  {5, 1025, 24, 10, ["💡", "💡", "👏", "👏", "🎯"]},
  {6, 1200, 16, 7, ["👏", "👏", "👏", "❤️", "🎉"]}
]

talk_seconds = 26 * 60

for {{slide, start, count, people, emojis}, index} <- Enum.with_index(slides) do
  window_end =
    case Enum.at(slides, index + 1) do
      {_, next_start, _, _, _} -> next_start
      nil -> talk_seconds - 30
    end

  window = window_end - start
  slide_audience = Enum.take(audience, people)

  for n <- 1..count do
    # The first reaction lands right as the slide appears. The rest bunch up
    # shortly after it, like a real audience reacting to a new slide.
    offset = if n == 1, do: start, else: start + round(window * :rand.uniform() ** 2)
    at = DateTime.add(started_at, offset, :second)

    Speechwave.Repo.insert!(%Speechwave.Reactions.Reaction{
      talk_session_id: session1.id,
      emoji: Enum.random(emojis),
      slide_number: slide,
      audience_id: Enum.random(slide_audience),
      inserted_at: at,
      updated_at: at
    })
  end
end

# Active session — connect the extension to this
{:ok, session2} = Talks.start_session(talk)

IO.puts("talk_slug=emojilove")
IO.puts("session1_id=#{session1.id}  (finished, has analytics)")
IO.puts("session2_id=#{session2.id}  (active — connect extension to this)")
IO.puts("")
IO.puts("Extension: connect to slug \"emojilove\"")
IO.puts("Analytics: http://localhost:4000  -> Dashboard -> Emoji Love")
