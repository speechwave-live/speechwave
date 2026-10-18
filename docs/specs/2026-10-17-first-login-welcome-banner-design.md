# First-login welcome banner

## Why

Every "Get started free" link on the marketing pages goes to the login page.
That is fine, but once a new user is signed in they land on `/users/settings`
with no hint of where to begin. The docs site has a Getting Started page that
answers exactly that question, and nothing in the app points to it except the
small "Help" link in the header.

## What it does

A new user sees a welcome banner directly below the header on every signed-in
page until they dismiss it. The text is:

> Welcome to Speechwave.live! Read the **Getting Started** guide for a quick
> tour, or click **Help** at the top of any page.

"Getting Started" is a link to the docs site's Getting Started page. It opens
in a new tab, the same as the Help link in the header. The banner has a close
button. Pressing it hides the banner immediately, with no page reload, and
records that the user has been welcomed. The banner never appears again for
that user, on any device.

The banner is not a flash message. A flash disappears on the next navigation,
and the first thing a new user does is click something. The banner stays until
the user decides they are done with it.

## Data

Add a nullable `welcomed_at` (`utc_datetime`) column to `users`.

- `nil` means the banner should show.
- A timestamp means the user dismissed it, and records when.

This replaces any attempt to detect "the first login" in the session code.
`confirmed_at` is set when the first session token is created, but the user
struct is stale at that moment and the OAuth and magic link paths would each
need their own hook. Keying the banner off `welcomed_at` works wherever the
user logs in, and it still behaves correctly if a new user signs in on a second
device before dismissing it on the first.

### Migration and backfill

The migration adds the column and then sets `welcomed_at = CURRENT_TIMESTAMP`
for every existing user, so only accounts created after this ships see the
banner. Without the backfill, every existing user would get a welcome message
on their next page load.

Generate it with `mix ecto.gen.migration add_welcomed_at_to_users`. The
column is not added to any `cast` list. The only writer is
`Accounts.mark_welcomed/1`, which sets `welcomed_at` to now only when it is
currently `nil` and returns `{:ok, user}` with the updated struct. Calling it
again leaves the original timestamp alone.

## Behavior

### Where it renders

In `Layouts.app/1` (`lib/speechwave_web/components/layouts.ex`), inside the
signed-in branch, between `</header>` and `<main>`. It renders when
`@current_scope.user.welcomed_at` is `nil` and the new `show_welcome` attr is
true. The signed-out branch and the public nav never show it.

The header is `fixed` with `pt-14` on `<main>` to clear it. The banner is a
normal block element inside a wrapper that carries the `pt-14`, so it sits
under the header and pushes the page content down rather than overlapping it.
Implementation detail for the plan: move the `pt-14` from `<main>` to a
wrapper that contains both the banner and `<main>`.

It is a function component (`welcome_banner/1`) in `Layouts`, with a stable DOM
id (`welcome-banner`) and an id on the close button (`welcome-banner-dismiss`)
for tests. Styling follows the existing tokens (`bg-surface`,
`border-hairline`, `text-ink`, `text-steel`), with a subtle fade-in. It must
read well at phone width: the text wraps and the close button stays reachable.

`show_welcome` is a boolean attr on `Layouts.app/1`, default `true`. The one
page that renders the layout outside a LiveView, the dev login page
(`dev_login_html/index.html.heex`), passes `show_welcome={false}`. That page can
have a signed-in `current_scope`, and a dead page has no LiveView to receive the
dismiss event, so a banner there could not be closed.

### Dismissing, with no reload

`Layouts.app/1` is a function component rendered by many LiveViews, so it has
no `handle_event` of its own. Rather than add a handler to each LiveView, one
hook in `UserAuth` catches the event for all of them.

The close button is:

    phx-click={
      JS.hide(to: "#welcome-banner", transition: "fade-out")
      |> JS.push("dismiss_welcome")
    }

`JS.hide` removes the banner on the client at once, and `JS.push` tells the
server in the background.

In `UserAuth`, the shared `mount_current_scope/2` helper attaches the handler.
Every `on_mount/4` clause (`:mount_current_scope`, `:require_authenticated`,
`:require_sudo_mode`, `:require_admin`) already calls it, so one change covers
every live session:

    Phoenix.LiveView.attach_hook(socket, :welcome_banner, :handle_event, &handle_welcome_event/3)

The handler matches `"dismiss_welcome"`, calls `Accounts.mark_welcomed/1`
for `socket.assigns.current_scope.user`, replaces `:current_scope` with a scope
built from the returned user, and returns `{:halt, socket}`. Replacing the
scope matters: if the LiveView re-renders later, `welcomed_at` is already set
in the assign, so the banner does not come back. Any other event returns
`{:cont, socket}` untouched.

Two details to get right:

- **No double attach.** The `:require_admin` live session lists both
  `:require_authenticated` and `:require_admin`, so `mount_current_scope/2` runs
  twice on one socket, and `attach_hook/4` raises if the same id is attached
  twice. Attach only when `:current_scope` was not already assigned, which is
  true only on the first call because `assign_new` leaves an existing value
  alone. Also attach only when the scope has a user, since a signed-out visitor
  has nothing to dismiss.
- **Idempotent write.** Two tabs open on the same new account can both send the
  event. `mark_welcomed/1` makes the second a no-op, so the first timestamp
  stays.

There is no new controller, route or redirect. The approach was chosen over a
POST-and-redirect controller action because the reload on dismissal felt
awkward, and the hook is also less code.

### The docs link

The Getting Started URL is the configured docs base plus
`getting-started.html`. That filename was checked against the docs repo
(`../docs/getting-started.md`, which builds to `getting-started.html`). Add a
`docs_url/1` style helper next to the existing private `docs_url/0` in
`Layouts`, so the banner and the Help link share one source for the base. In
dev the base is `http://localhost:4001` (the local Jekyll server), so the link
works in local testing too. Join the base and path so a trailing slash on the
base or a missing one both produce a single `/`.

### The existing "Welcome!" flash

`UserSessionController` sets `put_flash(:info, "Welcome!")` for every magic
link login (line 19) and every OAuth login (line 104). It fires on every
login, not only the first, and on a first login it would stack on top of the
new banner. Remove the plain "Welcome!" flash in both places. Keep the
"You're on the list!" flash for the magic link path when the user opted into
a Pro or Enterprise launch notice, since that confirms something the user
just asked for. When there is no such message, the magic link login sets no
flash at all.

## Out of scope

- A multi-step onboarding tour or checklist.
- Showing the banner to existing users.
- A "show the welcome again" control in Settings.
- Tracking whether the user actually clicked through to the docs.

## Tests

Following the project test guidelines (element ids, `has_element?`, no raw
HTML matching):

- `Accounts.mark_welcomed/1` sets the timestamp, and a second call does not
  change it.
- A user with `welcomed_at: nil` sees `#welcome-banner` on `/users/settings`
  and `/dashboard`, and the Getting Started link points at the docs base plus
  `getting-started.html`.
- A user with `welcomed_at` set does not see `#welcome-banner`.
- Clicking `#welcome-banner-dismiss` in a LiveView test sets `welcomed_at` in
  the database, and the banner is gone from the next render. Run it on one page
  from the plain authenticated session and one from the admin session
  (`/admin/stats`) to cover the double-mount case.
- Dismissing twice, or from a second LiveView for the same user, leaves the
  first timestamp in place and raises nothing.
- A signed-out visitor to a public LiveView (pricing, login) has no banner and
  no hook attached.
- The dev login page renders no banner even for a signed-in user with
  `welcomed_at: nil`.
- A magic link login and an OAuth login no longer set the plain "Welcome!"
  flash. The magic link "You're on the list!" flash still appears when
  requested.
- Factories and fixtures that create users should leave `welcomed_at` as `nil`
  by default, so tests of new-user behavior need no extra setup. Fixtures for
  tests that assert on other page content may need `welcomed_at` set so the
  banner does not interfere.
