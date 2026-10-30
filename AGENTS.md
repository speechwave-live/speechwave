This is a web application written using the Phoenix web framework (Phoenix 1.8, LiveView, Ecto, Tailwind v4).

Use Tidewave's tools for evaluating code, querying the database, etc.
Use `get_docs` to access documentation and the `get_source_location` tool to find module/function definitions.

## Project guidelines

- **Never use git worktrees.** Use feature branches instead.
- Run `mix precommit` when you are done with all changes and fix any pending issues
- Use `Req` for HTTP requests. **Avoid** `:httpoison`, `:tesla`, and `:httpc`

## Phoenix and LiveView

- **Always** begin LiveView templates with `<Layouts.app flash={@flash} current_scope={@current_scope} ...>`. A missing `current_scope` error means the route is in the wrong `live_session` or `current_scope` wasn't passed to `<Layouts.app>`
- `<.flash_group>` may only be called from `layouts.ex`
- Use `<.icon name="hero-...">` for icons, never `Heroicons` modules
- Use the imported `<.input>` for form inputs. If you pass your own `class`, no default classes are inherited, so style the input fully
- Forms: always `to_form/2` in the LiveView, `<.form for={@form} id="...">` and `@form[:field]` in the template. Never pass a changeset to the template
- Give key elements (forms, buttons, etc.) unique DOM ids so tests can target them
- Use streams for collections. The parent needs `phx-update="stream"` and an id, and each child uses the stream id as its DOM id. Streams can't be filtered or counted, so re-stream with `reset: true` and track counts in a separate assign
- A `phx-hook` needs a unique DOM id, and `phx-update="ignore"` if the hook manages its own DOM
- Write inline JS as colocated hooks (`<script :type={Phoenix.LiveView.ColocatedHook} name=".Name">`). **Never** use raw `<script>` tags in templates
- Avoid LiveComponents unless there is a strong, specific need

## JS and CSS

- Only the `app.js` and `app.css` bundles are supported. Import vendor deps into them instead of referencing external `src`/`href` in layouts
- Tailwind v4 has no `tailwind.config.js`. Keep the `@import "tailwindcss" source(none);` and `@source` lines in `app.css`
- **Never** use `@apply` in raw CSS
- daisyUI is still loaded for existing components. Write new components with plain Tailwind and don't add new daisyUI usage

## Authentication

- Handle auth at the router level. `phx.gen.auth` assigns `current_scope`, not `current_user`. Use `@current_scope.user` in templates and LiveViews
- Pass `current_scope` as the first argument to context functions and filter queries by `current_scope.user`
- Routes that require login go in the existing `live_session :require_authenticated_user` block (controllers: a scope piped through `:require_authenticated_user`)
- Routes that work with or without login go in the existing `live_session :current_user` block
- Never define a `live_session` name twice
- When adding a route, state which scope, `live_session`, and pipeline you chose, and why

## Elixir and Ecto

- Don't use `String.to_atom/1` on user input
- Predicate functions end in `?` and don't start with `is_`
- Don't nest multiple modules in one file
- Don't use `changeset[:field]` or other Access syntax on structs. Use `Ecto.Changeset.get_field/2` for changesets
- Use `Task.async_stream/3` with `timeout: :infinity` for concurrent enumeration
- Preload associations that templates will access
- Programmatically set fields such as `user_id` must not be in `cast`. Set them on the struct
- Generate migrations with `mix ecto.gen.migration name_with_underscores`

## Tests

- Start processes with `start_supervised!/1`
- Avoid `Process.sleep/1` and `Process.alive?/1`. Use `Process.monitor/1` and assert on the `:DOWN` message, or `:sys.get_state/1` to synchronize
- LiveView tests: use `element/2` and `has_element?/2` with the DOM ids from the templates, and don't assert against raw HTML. Prefer asserting element presence over text content
- Debug selector failures by printing a narrowed `LazyHTML.filter/2` result, not the whole page

## Codebase map

`.codesight/` is kept up to date by the pre-commit hook. Use it for orientation, then read the actual source before implementing.

- `.codesight/wiki/index.md`: where things live
- `.codesight/routes.md`: route map with methods, paths, and tags
- `.codesight/schema.md`: database models, fields, and relations
- `.codesight/CODESIGHT.md`: full context map (components, libraries, config, middleware, dependency graph)
