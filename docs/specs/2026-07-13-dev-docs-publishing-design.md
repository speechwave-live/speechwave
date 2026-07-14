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
- `docs/explainer/index.html` (the internal "Codebase Guide") from the
  `speechwave-live/speechwave` repo.
- `learn/elixir/lessons/*.html` (9 lesson pages, `0000`–`0008`) and
  `learn/elixir/reference/*.html` (9 reference cheatsheets) from the
  `learn/elixir` personal repo.
- A style-rule pass (see below) applied to these new pages *and* to the 5
  existing onboarding pages already on `docs.speechwave.live`
  (`index.md`, `getting-started.md`, `dashboard.md`, `extension.md`,
  `troubleshooting.md`).

**Out of scope:**
- `learn/elixir/learning-records/`, `NOTES.md`, `MISSION.md` — personal,
  first-person teaching-journal content, not meant for a public audience.
- `docs/decisions.md`, `docs/roadmap.md`, `docs/manual_tests.md`,
  `docs/specs/`, `docs/plans/` — internal engineering working documents.
- Any redesign/reskinning of the standalone HTML pages to visually match the
  just-the-docs theme (see "Approach" below).

## Approach

Three integration options were considered:

- **Full Jekyll conversion** of all 18 HTML pages plus the explainer into
  just-the-docs markdown — fully integrated nav/search, but a large rewrite
  (custom CSS, callout boxes, quiz interactivity) for content that already
  works well as-is. Rejected as disproportionate effort.
- **Keep standalone HTML, add thin markdown landing pages** — minimal
  rewrite, ships fast, preserves the lessons' interactive quizzes and the
  explainer's existing design exactly as authored.
- **Hybrid**: same as above, plus converting the 9 reference cheatsheets to
  real markdown pages since they're short and static.

**Decision: the second option** (thin landing pages, standalone HTML
elsewhere), with one addition — a back-navigation link is added to the
header of every standalone page (explainer, lessons, and reference
cheatsheets) so readers can always get back to `docs.speechwave.live`'s nav
without relying on the browser's back button.

## Site structure

New pages/assets in the `speechwave-live/docs` repo:

```
/dev.md                          — landing page, nav_order after the existing
                                    5 onboarding pages. Introduces the section,
                                    links to the explainer and the course.
/dev/explainer.html               — adapted copy of docs/explainer/index.html
/dev/course.md                    — course landing page: lists lessons and
                                    reference cheatsheets with short blurbs
/dev/course/lessons/000X-*.html   — adapted copies of the 9 lesson pages
/dev/course/reference/*.html      — adapted copies of the 9 reference pages
```

Only `/dev.md` and `/dev/course.md` are real Jekyll pages participating in
the just-the-docs sidebar and search index. The explainer, lessons, and
reference pages are static HTML reached by clicking through from those two
landing pages — they do not appear in the global sidebar.

## Content adaptation

Every copied page (explainer, lessons, reference cheatsheets) gets three
changes before publishing:

1. **Back-navigation** — a small header link ("← docs.speechwave.live")
   added to the page's existing header markup.
2. **GitHub linking** — bare repo-relative paths and "open your SpeechWave
   project" framing are replaced with links to the actual public repo
   (`github.com/speechwave-live/speechwave/blob/main/...`), since readers
   won't have a local checkout.
3. **Writing style pass** — prose is edited to follow `tmp/writing_docs.md`:
   casual-expertise tone, no AI writing clichés, no em/en-dashes used to
   separate phrases, sentence case for headings. This pass also applies to
   the 5 existing onboarding pages.

The explainer additionally requires a **sanitization read-through**: since
it was written for an internal audience, it must be read end to end and any
content that shouldn't be public (internal-only architecture notes, anything
adjacent to auth/security internals) must be flagged and confirmed with
Tracy before that content goes live. **This is a hard gate — nothing from
the explainer ships until this confirmation happens.**

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

- Local Jekyll build (`bundle exec jekyll serve`) confirms the new nav
  entry renders and all pages display correctly before pushing.
- A link-check pass confirms every GitHub-blob link and internal cross-link
  (landing pages ↔ lessons ↔ cheatsheets ↔ back-nav) resolves.
- The explainer sanitization gate (above) has been explicitly confirmed by
  Tracy.
- Style-rule compliance (`tmp/writing_docs.md`) is spot-checked on every
  touched page, both new and existing.
