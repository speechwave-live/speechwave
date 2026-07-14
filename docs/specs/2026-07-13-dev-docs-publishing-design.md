# Publishing developer docs on docs.speechwave.live — Design

## Goal

Add a "For developers" section to `docs.speechwave.live` containing the
codebase explainer and the Elixir-for-Ruby-developers course, so that:

- Curious users and prospective contributors can see how Speechwave is built.
- The course becomes a piece of content to share when announcing Speechwave
  to the Elixir community, since it uses the (public) Speechwave codebase as
  its running example.

## Scope

**In scope:**
- `docs/explainer.md` and `docs/explainer/index.html` — two files from the
  `speechwave-live/speechwave` repo that have diverged (see "A discovery:
  two diverging explainers" below). Both are retired; their content is
  reconciled into a new set of Jekyll pages that becomes the sole canonical
  explainer, maintained going forward in the docs repo.
- `learn/elixir/lessons/*.html` (9 lesson pages, `0000`–`0008`) and
  `learn/elixir/reference/*.html` (9 reference cheatsheets) from the
  `learn/elixir` personal repo.
- A style-rule pass (see below) applied to these new pages *and* to the 5
  existing onboarding pages already on `docs.speechwave.live`
  (`index.md`, `getting-started.md`, `dashboard.md`, `extension.md`,
  `troubleshooting.md`).
- Updating `README.md` in the speechwave repo so its explainer link points
  at the new public location instead of the now-deleted `docs/explainer.md`.

**Out of scope:**
- `learn/elixir/learning-records/`, `NOTES.md`, `MISSION.md` — personal,
  first-person teaching-journal content, not meant for a public audience.
- `docs/decisions.md`, `docs/roadmap.md`, `docs/manual_tests.md`,
  `docs/specs/`, `docs/plans/` — internal engineering working documents.
- Any redesign/reskinning of the course's standalone HTML pages to visually
  match the just-the-docs theme (see "Approach" below) — this applies only
  to the explainer, which is converting to native Jekyll pages.

## A discovery: two diverging explainers

While designing this, we found `docs/explainer/index.html` (the interactive
HTML "Codebase Guide" originally planned for publishing) is stale: it was
last touched 2026-05-09 and has 15 commits, while `docs/explainer.md` (a
plain-markdown walkthrough, linked from `README.md`) has been actively kept
current through 2026-07-05 with 24 commits. The May spec's intent was for
the HTML version to replace the markdown one, but in practice the markdown
file is what actually got maintained — the HTML version is missing about
two months of architecture changes (Presence tracking, `AuthThrottle`, the
dashboard-flow replacement of the old admin flow, the switch from
`MutationObserver` to polling for slide tracking, and more).

This is why the design below converts the explainer to real Jekyll markdown
pages rather than publishing the HTML file as-is: a single diffable,
natively-navigable source in the same repo it's published from is what
prevents this kind of drift from happening again. The course keeps its
original standalone-HTML approach (below) since it doesn't have this
drift problem — `learn/elixir` is a single, actively-maintained source.

## Approach

Three integration options were considered for the 18 course HTML pages plus
the explainer:

- **Full Jekyll conversion** of everything into just-the-docs markdown —
  fully integrated nav/search, but a large rewrite (custom CSS, callout
  boxes, quiz interactivity) for content that already works well as-is.
- **Keep standalone HTML, add thin markdown landing pages** — minimal
  rewrite, ships fast, preserves the lessons' interactive quizzes and the
  explainer's existing design exactly as authored.
- **Hybrid**: same as above, plus converting the 9 reference cheatsheets to
  real markdown pages since they're short and static.

**Decision: a mixed approach**, applying each option where it fits best:

- **The course** (lessons + reference cheatsheets) uses the standalone-HTML
  option: thin markdown landing page, static HTML elsewhere, since
  `learn/elixir` isn't a drift risk and the quizzes are worth preserving
  exactly as authored.
- **The explainer** uses full Jekyll conversion instead, specifically
  because of the drift problem above — a single canonical, diffable,
  natively-navigable source is the fix, not a formatting preference.

Every standalone page (course lessons, reference cheatsheets) gets a
back-navigation link added to its header so readers can always get back to
`docs.speechwave.live`'s nav without relying on the browser's back button.
The explainer's chapter pages get this back-navigation for free, since
they're now real Jekyll pages inside the just-the-docs nav.

## Site structure

New pages/assets in the `speechwave-live/docs` repo:

```
/dev.md                            — landing page, nav_order after the
                                      existing 5 onboarding pages ("For
                                      developers", has_children: true).
                                      Introduces the section, links to the
                                      explainer and the course.
/dev/explainer/index.md            — explainer landing page (parent: For
                                      developers, has_children: true).
                                      Short intro + chapter list.
/dev/explainer/overview.md
/dev/explainer/data-model.md
/dev/explainer/authentication.md
/dev/explainer/emoji-journey.md
/dev/explainer/websockets.md
/dev/explainer/plans-limits.md
/dev/explainer/supervision-tree.md
/dev/explainer/db-backup.md
/dev/explainer/chrome-extension.md
/dev/explainer/analytics.md        — one file per chapter (parent:
                                      Codebase explainer, grand_parent: For
                                      developers), same 10 chapters as the
                                      old index.html.
/dev/course.md                     — course landing page (parent: For
                                      developers): lists lessons and
                                      reference cheatsheets with short
                                      blurbs
/dev/course/lessons/000X-*.html    — adapted copies of the 9 lesson pages
/dev/course/reference/*.html       — adapted copies of the 9 reference pages
```

just-the-docs (confirmed installed: v0.12.0) supports 3-level nav via
`parent`/`grand_parent` front matter, so this reproduces the original
HTML's chapter sidebar natively: **For developers → Codebase explainer →
[chapter]**, alongside **For developers → Elixir course**. The course's
lessons and reference pages remain static HTML reached by clicking through
from `/dev/course.md` — they do not appear in the global sidebar, unchanged
from the original design.

Any shared CSS the explainer chapters need (the architecture diagram,
callouts, info-cards, schema tables, collapsible sections) moves into the
docs site's `_sass` rather than being duplicated per chapter file. Shared
JS (the collapsible-section toggle and the "Emoji journey" chapter's
interactive step-through walkthrough) moves into a site asset included via
`_includes/head_custom.html` or a per-page script include, rather than each
chapter re-embedding it.

## Content adaptation

### Explainer

Converting the explainer is more than a copy-and-tweak, since it involves
reconciling two diverged sources into one:

1. **Reconciliation** — for each of the 10 chapters, compare
   `docs/explainer.md` (current) against the matching section of
   `docs/explainer/index.html` (stale but better-formatted) and write one
   accurate chapter reflecting the current architecture, using
   `explainer.md`'s facts and `index.html`'s presentation (diagrams,
   tables, callouts) where applicable.
2. **Splitting** — each reconciled chapter becomes its own markdown file
   per the site structure above, with `parent`/`grand_parent`/`nav_order`
   front matter.
3. **GitHub linking** — repo-relative paths become links to
   `github.com/speechwave-live/speechwave/blob/main/...`, since readers
   won't have a local checkout.
4. **Writing style pass** — prose is edited to follow `tmp/writing_docs.md`
   (casual-expertise tone, no AI writing clichés, no em/en-dashes used to
   separate phrases, sentence case for headings).

This requires a **sanitization read-through**: since the source material
was written for an internal audience, it must be read end to end and any
content that shouldn't be public (internal-only architecture notes,
anything adjacent to auth/security internals) must be flagged and confirmed
with Tracy before that content goes live. **This is a hard gate — nothing
from the explainer ships until this confirmation happens.**

Once the new chapter pages are live, `docs/explainer.md` and
`docs/explainer/index.html` are deleted from the speechwave repo, and
`README.md`'s explainer link is updated to point at
`https://docs.speechwave.live/dev/explainer/`. The docs repo becomes the
sole home for this content — future architecture-doc updates happen by
editing the Jekyll markdown files directly, accepting the cross-repo
context switch during dev work as the cost of having one source of truth
instead of two drifting ones.

### Course (lessons + reference cheatsheets)

Every copied page gets three changes before publishing:

1. **Back-navigation** — a small header link ("← docs.speechwave.live")
   added to the page's existing header markup.
2. **GitHub linking** — bare repo-relative paths and "open your SpeechWave
   project" framing are replaced with links to the actual public repo
   (`github.com/speechwave-live/speechwave/blob/main/...`), since readers
   won't have a local checkout.
3. **Writing style pass** — prose is edited to follow `tmp/writing_docs.md`:
   casual-expertise tone, no AI writing clichés, no em/en-dashes used to
   separate phrases, sentence case for headings.

The style-rule pass (rule 3 above) also applies to the 5 existing
onboarding pages already on `docs.speechwave.live`.

## Course publish workflow (repeatable)

`learn/elixir` is Tracy's live, ongoing personal learning repo — more
lessons will be written after this initial publish. Rather than a one-time
snapshot, this design includes a short, manual checklist
(`learn/elixir/PUBLISHING.md`) for porting a new lesson or cheatsheet to the
docs site:

1. Copy the lesson/cheatsheet HTML from `learn/elixir` into
   `speechwave-live/docs/dev/course/...`.
2. Apply the three content adaptations above (back-nav header, GitHub links,
   style-rule pass).
3. Add an entry and short blurb to `/dev/course.md`.
4. Rebuild/preview the Jekyll site locally, then commit and push.

This is intentionally a manual checklist, not a script: each lesson needs a
human read-through anyway, since style-rule compliance and which files to
link on GitHub aren't purely mechanical and vary lesson to lesson.

## Verification and acceptance

- Local Jekyll build (`bundle exec jekyll serve`) confirms the 3-level nav
  (For developers → Codebase explainer → chapter, and For developers →
  Elixir course) renders correctly, and that all pages display correctly
  before pushing.
- Reconciliation accuracy spot-check: the specific deltas identified between
  `explainer.md` and `index.html` (Presence tracking, `AuthThrottle`, the
  dashboard-flow replacement of the old admin flow, `MutationObserver` →
  polling for slide tracking) are all represented correctly in the new
  chapter pages.
- A link-check pass confirms every GitHub-blob link and internal cross-link
  (landing pages ↔ chapters ↔ lessons ↔ cheatsheets ↔ back-nav) resolves.
- The explainer sanitization gate (above) has been explicitly confirmed by
  Tracy.
- Style-rule compliance (`tmp/writing_docs.md`) is spot-checked on every
  touched page, both new and existing.
- `docs/explainer.md` and `docs/explainer/index.html` no longer exist in the
  speechwave repo, and `README.md`'s explainer link resolves to the new
  public URL.
