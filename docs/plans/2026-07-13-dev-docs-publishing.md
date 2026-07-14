# Dev docs publishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the Speechwave codebase explainer and the Elixir-for-Ruby-developers course as a new "For developers" section on `docs.speechwave.live`.

**Architecture:** Three repos are involved. `speechwave-live/speechwave` holds the explainer source (read-only in this plan — the internal copy is untouched; only an adapted copy is published elsewhere). `learn/elixir` holds the course source (read-only except for one new checklist file). `speechwave-live/docs` is the Jekyll/just-the-docs site and is where nearly all new files and edits land: two new markdown landing pages plus copied-and-adapted standalone HTML for the explainer, 9 lessons, and 9 reference cheatsheets.

**Tech Stack:** Jekyll 4.4 + just-the-docs theme (Ruby/Bundler), static HTML/CSS/JS for the explainer and course pages, Markdown with Jekyll front matter for the two landing pages.

## Global Constraints

- **Repo roles:** `speechwave-live/speechwave` (path `docs/explainer/index.html`) is read-only — do not edit it. `learn/elixir` is read-only except for adding `PUBLISHING.md`. `speechwave-live/docs` is the primary write target for this plan.
- **Explainer sanitization is a hard gate.** Task 2 must get Tracy's explicit confirmation before Task 3 (publishing the explainer) starts.
- **Back-navigation target URL:** `https://docs.speechwave.live/` — every standalone page (explainer, lessons, reference cheatsheets) gets a back-link to this URL.
- **GitHub link base URL:** `https://github.com/speechwave-live/speechwave/blob/main/` — any repo-relative path mentioned in prose or code comments on a published page becomes a link built from this base.
- **Writing style rules** (from `tmp/writing_docs.md` in the speechwave repo, apply to every touched page, new and existing):
  - Casual-expertise tone: friendly, talented teacher explaining complex topics simply.
  - Simple language, not flowery or dramatic, but still compelling.
  - Avoid AI writing clichés: "not just X, but Y", "the real X is Y", "honestly", "underscores/highlights its importance", "a vital/significant/crucial/pivotal/key role/moment".
  - No em-dashes, en-dashes, or hyphens used to separate phrases.
  - Sentence case for headings and subheadings.
- **Commit format:** conventional commits (`docs:`, `style:`, `fix:`), one commit per task, made in whichever repo that task modifies.
- **No new dependencies:** don't add gems (e.g. html-proofer) to the docs site's `Gemfile`. Verification uses `jekyll build` plus plain shell scripting.

---

### Task 1: Create the "For developers" landing pages

**Files:**
- Create: `speechwave-live/docs/dev.md`
- Create: `speechwave-live/docs/dev/course.md`

**Interfaces:**
- Produces: the URLs `/dev.html` and `/dev/course.html`, which Tasks 3-5 link into (`/dev/explainer.html`, `/dev/course/lessons/*.html`, `/dev/course/reference/*.html`). Those target files don't exist yet — that's expected, links will 404 until Tasks 3-5 land. This task's own build/render check doesn't depend on them.

- [ ] **Step 1: Write `dev.md`**

```markdown
---
title: For developers
nav_order: 6
has_children: true
---

# For developers

Speechwave is built in the open. This section is for anyone who wants to see how it works under the hood, whether you're evaluating the codebase, thinking about contributing, or just curious.

## Codebase explainer

A guided tour of how Speechwave is put together: the data model, authentication, the emoji journey from a phone tap to a slide overlay, WebSockets, and the infrastructure that keeps it running.

[Read the codebase explainer](/dev/explainer.html)

## Elixir for Ruby developers

A short course written while learning Elixir and Phoenix LiveView on the real Speechwave codebase. If you know Ruby and want to get comfortable reading and writing Elixir, start here.

[Start the course](/dev/course.html)
```

- [ ] **Step 2: Write `dev/course.md`**

```markdown
---
title: Elixir course
parent: For developers
nav_order: 1
---

# Elixir for Ruby developers

Nine short lessons that teach Elixir and Phoenix LiveView using real code from the Speechwave codebase. Written for developers who already know Ruby and want to read, understand, and change Elixir code with confidence.

Each lesson links to the actual files it discusses in the [public Speechwave repo](https://github.com/speechwave-live/speechwave).

## Lessons

1. [The old sock introduction](/dev/course/lessons/0000-introduction.html)
2. [Pattern matching](/dev/course/lessons/0001-pattern-matching.html)
3. [The pipe operator and data transformation](/dev/course/lessons/0002-pipe-operator.html)
4. [Modules, structs, and the shape of an Elixir project](/dev/course/lessons/0003-modules-and-structs.html)
5. [The LiveView lifecycle](/dev/course/lessons/0004-liveview-lifecycle.html)
6. [Ecto queries](/dev/course/lessons/0005-ecto-queries.html)
7. [Testing with ExUnit](/dev/course/lessons/0006-testing-with-exunit.html)
8. [GenServer and stateful processes](/dev/course/lessons/0007-genserver.html)
9. [Debugging with IEx and dbg](/dev/course/lessons/0008-debugging.html)

## Reference

Quick-reference sheets to keep open while you work.

- [Accessing docs](/dev/course/reference/accessing-docs.html)
- [Debugging cheatsheet](/dev/course/reference/debugging-cheatsheet.html)
- [Ecto queries cheatsheet](/dev/course/reference/ecto-queries-cheatsheet.html)
- [Elixir glossary](/dev/course/reference/glossary.html)
- [HEEx template syntax](/dev/course/reference/heex-template-syntax.html)
- [Operators](/dev/course/reference/operators.html)
- [Pipe operator and Enum cheatsheet](/dev/course/reference/pipe-and-enum-cheatsheet.html)
- [Supervision tree](/dev/course/reference/supervision-tree.html)
- [ExUnit testing cheatsheet](/dev/course/reference/testing-cheatsheet.html)
```

- [ ] **Step 3: Build the site locally and check the nav**

Run: `cd /Users/tracy/projects/speechwave-live/docs && bundle exec jekyll build`
Expected: build succeeds with no errors; `_site/dev.html` and `_site/dev/course.html` exist.

Then run: `grep -o 'For developers' _site/dev.html | head -1 && grep -o 'Elixir course' _site/dev/course.html | head -1`
Expected: both greps print their match (confirms titles rendered).

- [ ] **Step 4: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/docs
git add dev.md dev/course.md
git commit -m "docs: add For developers landing pages"
```

---

### Task 2: Sanitization read-through of the explainer

**Files:**
- Read: `speechwave-live/speechwave/docs/explainer/index.html` (no edits in this task)

**Interfaces:**
- Produces: a written list of flagged passages (chapter name + short quote + reason), delivered as a message to Tracy. Task 3 cannot start until Tracy has responded to this list.

- [ ] **Step 1: Read the full explainer**

Read `speechwave-live/speechwave/docs/explainer/index.html` end to end. It has 10 chapters: Overview, Data Model, Authentication, Emoji Journey, WebSockets, Plans & Limits, Supervision Tree, DB Backup, Chrome Extension, Analytics.

- [ ] **Step 2: Flag anything that shouldn't be public**

Apply this rubric — flag a passage if it:
- Names specific rate limits, quotas, or anti-abuse thresholds that would help someone game the system (look closely at "Plans & Limits").
- Describes auth token generation/verification mechanics beyond a conceptual level, e.g. exact secret derivation, session token format internals (look closely at "Authentication").
- Names concrete infrastructure details useful to an attacker: backup file paths/locations, credentials, internal hostnames, non-public admin routes (look closely at "DB Backup" and "Supervision Tree").
- Reveals unreleased/internal-only roadmap items or business specifics (pricing internals, unannounced features) not meant for public view.

For each flagged passage, note: chapter name, a short quote, and why it's flagged.

- [ ] **Step 3: Present findings to Tracy**

Send the flagged list (or "nothing flagged" if the read-through turns up nothing) as a message. Do not proceed to Task 3 until Tracy has explicitly confirmed what to redact, rephrase, or leave as-is.

---

### Task 3: Adapt and publish the codebase explainer

**Files:**
- Read: `speechwave-live/speechwave/docs/explainer/index.html` (source, unchanged)
- Create: `speechwave-live/docs/dev/explainer.html` (adapted copy)

**Interfaces:**
- Consumes: Tracy's sanitization confirmation from Task 2.
- Produces: `/dev/explainer.html`, linked from `/dev.html` (Task 1).

- [ ] **Step 1: Copy the source file**

```bash
cp /Users/tracy/projects/speechwave-live/speechwave/docs/explainer/index.html \
   /Users/tracy/projects/speechwave-live/docs/dev/explainer.html
```

- [ ] **Step 2: Apply Task 2's confirmed redactions/rephrasing**

Edit `dev/explainer.html` to redact or rephrase exactly what Tracy confirmed in Task 2. If Tracy confirmed nothing needed changes, skip this step.

- [ ] **Step 3: Add the back-navigation link**

In `dev/explainer.html`, find this existing CSS rule (originally around line 49):

```css
.top-bar-subtitle { font-size: 13px; color: var(--text-subtle); }
```

Add immediately after it:

```css
.top-bar-back { margin-left: auto; font-size: 13px; color: var(--text-subtle); text-decoration: none; }
.top-bar-back:hover { color: var(--accent-light); }
```

Find the existing header (originally around line 374-378):

```html
<header class="top-bar">
  <span class="top-bar-logo">Speechwave</span>
  <span class="top-bar-sep">/</span>
  <span class="top-bar-subtitle">Codebase Guide</span>
</header>
```

Add the back-link as the last child:

```html
<header class="top-bar">
  <span class="top-bar-logo">Speechwave</span>
  <span class="top-bar-sep">/</span>
  <span class="top-bar-subtitle">Codebase Guide</span>
  <a class="top-bar-back" href="https://docs.speechwave.live/">&larr; docs.speechwave.live</a>
</header>
```

- [ ] **Step 4: Replace repo-relative paths with GitHub links**

Search the file for code-path mentions (e.g. `lib/fireworks.js`, `lib/speechwave_web/...`, `test/...`). For each one, wrap it in a link using the base URL from Global Constraints, e.g.:

```html
<a href="https://github.com/speechwave-live/speechwave/blob/main/lib/fireworks.js">lib/fireworks.js</a>
```

- [ ] **Step 5: Apply the writing style pass**

Read through the full file and edit prose to match the Global Constraints style rules (casual-expertise tone, no clichés, no dash-separated phrases, sentence case headings).

- [ ] **Step 6: Run the automated style/link checks**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -n "—\|–" dev/explainer.html
grep -inE "not just .* but|the real .* is|\bhonestly\b|underscores (its|the)|highlights (its|the)|(vital|significant|crucial|pivotal|key) (role|moment)" dev/explainer.html
```

Expected: both commands print no matches. Fix any that show up and re-run.

- [ ] **Step 7: Build and visually check**

```bash
bundle exec jekyll build
open _site/dev/explainer.html
```

Confirm the back-link renders in the top-right of the header and clicking it goes to `https://docs.speechwave.live/`.

- [ ] **Step 8: Commit**

```bash
git add dev/explainer.html
git commit -m "docs: publish adapted codebase explainer to /dev/explainer.html"
```

---

### Task 4: Adapt and publish the reference cheatsheets

**Files:**
- Read (source, unchanged): `learn/elixir/reference/accessing-docs.html`, `debugging-cheatsheet.html`, `ecto-queries-cheatsheet.html`, `glossary.html`, `heex-template-syntax.html`, `operators.html`, `pipe-and-enum-cheatsheet.html`, `supervision-tree.html`, `testing-cheatsheet.html`
- Create: the same 9 filenames under `speechwave-live/docs/dev/course/reference/`

**Interfaces:**
- Produces: `/dev/course/reference/*.html` (9 files), linked from `/dev/course.html` (Task 1).

- [ ] **Step 1: Copy all 9 files**

```bash
mkdir -p /Users/tracy/projects/speechwave-live/docs/dev/course/reference
cp /Users/tracy/projects/learn/elixir/reference/*.html \
   /Users/tracy/projects/speechwave-live/docs/dev/course/reference/
```

- [ ] **Step 2: Add the back-navigation link to each of the 9 files**

For each file, add this to the `<style>` block (append near the end of the existing rules):

```css
.back-nav { display: block; font-size: 0.85em; color: #718096; text-decoration: none; margin-bottom: 1.5em; }
.back-nav:hover { color: #4a5568; }
```

And insert immediately after the `<body>` tag:

```html
<a class="back-nav" href="https://docs.speechwave.live/">&larr; docs.speechwave.live</a>
```

- [ ] **Step 3: Replace repo-relative paths with GitHub links**

In each file, wrap any repo-relative code path in a link using the base URL from Global Constraints, same pattern as Task 3 Step 4.

- [ ] **Step 4: Apply the writing style pass**

Read each of the 9 files and edit prose per the Global Constraints style rules.

- [ ] **Step 5: Run the automated style checks across all 9 files**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -n "—\|–" dev/course/reference/*.html
grep -inE "not just .* but|the real .* is|\bhonestly\b|underscores (its|the)|highlights (its|the)|(vital|significant|crucial|pivotal|key) (role|moment)" dev/course/reference/*.html
```

Expected: no matches. Fix and re-run if anything shows up.

- [ ] **Step 6: Build and spot-check one file**

```bash
bundle exec jekyll build
open _site/dev/course/reference/glossary.html
```

Confirm the back-link appears at the top and works.

- [ ] **Step 7: Commit**

```bash
git add dev/course/reference/
git commit -m "docs: publish adapted reference cheatsheets under /dev/course/reference"
```

---

### Task 5: Adapt and publish the course lessons

**Files:**
- Read (source, unchanged): `learn/elixir/lessons/0000-introduction.html` through `0008-debugging.html` (9 files)
- Create: the same 9 filenames under `speechwave-live/docs/dev/course/lessons/`

**Interfaces:**
- Produces: `/dev/course/lessons/*.html` (9 files), linked from `/dev/course.html` (Task 1).

- [ ] **Step 1: Copy all 9 files**

```bash
mkdir -p /Users/tracy/projects/speechwave-live/docs/dev/course/lessons
cp /Users/tracy/projects/learn/elixir/lessons/*.html \
   /Users/tracy/projects/speechwave-live/docs/dev/course/lessons/
```

- [ ] **Step 2: Add the back-navigation link to each of the 9 files**

Same CSS and HTML snippet as Task 4 Step 2 — append the `.back-nav` CSS rule to each file's `<style>` block and insert the `<a class="back-nav">` link immediately after `<body>`.

- [ ] **Step 3: Adapt the "open your project" framing to the public repo**

These lessons assume the reader has SpeechWave checked out locally (e.g. "Open your SpeechWave project alongside this lesson. Every example comes from your actual codebase."). Since the repo is now public, reframe these mentions to point at the public GitHub repo instead, e.g.:

```html
<p>Open the <a href="https://github.com/speechwave-live/speechwave">public Speechwave repo</a> alongside this lesson, or follow the file links below &mdash; every example comes from the real codebase.</p>
```

Adjust wording per-lesson to fit context; don't do a blind find-replace since the surrounding sentence varies lesson to lesson.

- [ ] **Step 4: Replace repo-relative paths with GitHub links**

Same pattern as Task 3 Step 4 and Task 4 Step 3 — wrap file paths in links to `https://github.com/speechwave-live/speechwave/blob/main/<path>`.

- [ ] **Step 5: Apply the writing style pass**

Read each of the 9 lessons and edit prose per the Global Constraints style rules. Be careful editing inside the quiz `<script>` blocks — only touch visible prose/labels, not the JS logic that checks answers.

- [ ] **Step 6: Run the automated style checks across all 9 files**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -n "—\|–" dev/course/lessons/*.html
grep -inE "not just .* but|the real .* is|\bhonestly\b|underscores (its|the)|highlights (its|the)|(vital|significant|crucial|pivotal|key) (role|moment)" dev/course/lessons/*.html
```

Expected: no matches (aside from any the sanitization step in Task 3 intentionally left, which doesn't apply here). Fix and re-run if anything shows up.

- [ ] **Step 7: Build and verify quiz interactivity survived**

```bash
bundle exec jekyll build
open _site/dev/course/lessons/0001-pattern-matching.html
```

Manually click through the quiz on this page and confirm selecting an answer still shows the correct/wrong feedback (proves the edits didn't break the inline JS).

- [ ] **Step 8: Commit**

```bash
git add dev/course/lessons/
git commit -m "docs: publish adapted Elixir course lessons under /dev/course/lessons"
```

---

### Task 6: Apply the writing style pass to existing onboarding pages

**Files:**
- Modify: `speechwave-live/docs/index.md`
- Modify: `speechwave-live/docs/getting-started.md`
- Modify: `speechwave-live/docs/dashboard.md`
- Modify: `speechwave-live/docs/extension.md`
- Modify: `speechwave-live/docs/troubleshooting.md`

**Interfaces:**
- None — this task only edits prose, no structural/link changes.

- [ ] **Step 1: Read and edit each of the 5 files**

Read each file and edit prose per the Global Constraints writing style rules (casual-expertise tone, no clichés, no dash-separated phrases, sentence case headings). Preserve all existing front matter (`title`, `nav_order`) and links exactly.

- [ ] **Step 2: Run the automated style checks**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -n "—\|–" index.md getting-started.md dashboard.md extension.md troubleshooting.md
grep -inE "not just .* but|the real .* is|\bhonestly\b|underscores (its|the)|highlights (its|the)|(vital|significant|crucial|pivotal|key) (role|moment)" index.md getting-started.md dashboard.md extension.md troubleshooting.md
```

Expected: no matches. Fix and re-run if anything shows up.

- [ ] **Step 3: Build and confirm the site still renders**

```bash
bundle exec jekyll build
grep -c "<h1" _site/index.html _site/getting-started.html _site/dashboard.html _site/extension.html _site/troubleshooting.html
```

Expected: each file prints a count of at least 1 (confirms the page still has a heading and built without errors).

- [ ] **Step 4: Commit**

```bash
git add index.md getting-started.md dashboard.md extension.md troubleshooting.md
git commit -m "style: apply writing-rules pass to existing onboarding pages"
```

---

### Task 7: Write the repeatable course-publishing checklist

**Files:**
- Create: `learn/elixir/PUBLISHING.md`

**Interfaces:**
- None — standalone reference document for future manual use.

- [ ] **Step 1: Write the checklist**

```markdown
# Publishing a lesson or reference page

Steps to port a new lesson or reference cheatsheet from this repo to
docs.speechwave.live once it's ready to share publicly.

1. Copy the file from `lessons/` or `reference/` here into the matching
   folder in `speechwave-live/docs/dev/course/` (same filename).
2. Add the back-navigation link:
   - Append to the file's `<style>` block:
     ```css
     .back-nav { display: block; font-size: 0.85em; color: #718096; text-decoration: none; margin-bottom: 1.5em; }
     .back-nav:hover { color: #4a5568; }
     ```
   - Insert immediately after `<body>`:
     ```html
     <a class="back-nav" href="https://docs.speechwave.live/">&larr; docs.speechwave.live</a>
     ```
3. Replace any repo-relative path mentions (e.g. `lib/foo.ex`) with a link
   to `https://github.com/speechwave-live/speechwave/blob/main/<path>`.
   If the lesson assumes a local checkout, adjust the wording to point at
   the public repo instead.
4. Apply the writing style rules from
   `speechwave-live/speechwave/tmp/writing_docs.md`: casual-expertise tone,
   no AI clichés, no dash-separated phrases, sentence case headings.
5. Add an entry to `speechwave-live/docs/dev/course.md` under Lessons or
   Reference, linking to the new page.
6. Build and preview locally:
   ```bash
   cd /Users/tracy/projects/speechwave-live/docs
   bundle exec jekyll build
   open _site/dev/course/lessons/<file>.html   # or reference/<file>.html
   ```
   If the page has a quiz, click through it to confirm the JS still works.
7. Commit and push in the `speechwave-live/docs` repo.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/tracy/projects/learn/elixir
git add PUBLISHING.md
git commit -m "docs: add checklist for publishing lessons to docs.speechwave.live"
```

---

### Task 8: Final full-site verification

**Files:**
- None created or modified — verification only. Fix-up commits go in whichever repo/file the issue is found in.

**Interfaces:**
- Consumes: every file created/modified in Tasks 1-6.

- [ ] **Step 1: Full build**

```bash
cd /Users/tracy/projects/speechwave-live/docs
bundle exec jekyll build
```

Expected: build succeeds with no errors or warnings about missing files.

- [ ] **Step 2: Check internal links resolve**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -rho 'href="/dev[^"]*"' dev.md dev/course.md | sed 's/href="//;s/"$//' | while read -r path; do
  file="_site${path}"
  if [ ! -f "$file" ]; then
    echo "MISSING: $path"
  fi
done
```

Expected: no output (every internal `/dev/...` link has a matching built file). Fix any `MISSING` results before continuing.

- [ ] **Step 3: Check external GitHub links resolve**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -rhoE 'https://github\.com/speechwave-live/speechwave[^"]*' dev/explainer.html dev/course/lessons/*.html dev/course/reference/*.html | sort -u | while read -r url; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  if [ "$code" != "200" ]; then
    echo "BROKEN ($code): $url"
  fi
done
```

Expected: no output. Fix any `BROKEN` results (typo'd path, renamed file) before continuing.

- [ ] **Step 4: Re-run the full style-rule grep across every touched file**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -n "—\|–" dev.md dev/course.md dev/explainer.html dev/course/lessons/*.html dev/course/reference/*.html index.md getting-started.md dashboard.md extension.md troubleshooting.md
```

Expected: no matches.

- [ ] **Step 5: Manual spot-check**

Open `_site/dev.html`, `_site/dev/course.html`, `_site/dev/explainer.html`, one lesson, and one reference page in a browser. Confirm: the just-the-docs sidebar shows "For developers" with "Elixir course" nested under it, both landing pages link out correctly, and every standalone page's back-link returns to `https://docs.speechwave.live/`.

- [ ] **Step 6: Push**

Once everything above passes, ask Tracy whether to push the `speechwave-live/docs` and `learn/elixir` commits to their remotes (this plan does not push automatically).
