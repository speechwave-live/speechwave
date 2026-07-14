# Dev docs publishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the Speechwave codebase explainer and the Elixir-for-Ruby-developers course as a new "For developers" section on `docs.speechwave.live`.

**Architecture:** Three repos are involved. `speechwave-live/speechwave` holds the two (diverged) explainer sources, `docs/explainer.md` and `docs/explainer/index.html` — both are read-only during this plan and get deleted once migrated. `learn/elixir` holds the course source (read-only except for one new checklist file). `speechwave-live/docs` is the Jekyll/just-the-docs site and is where nearly all new files land: the explainer converts to native Jekyll markdown chapter pages (fixing the drift between its two old sources), while the course keeps its original standalone HTML, adapted and linked from thin markdown landing pages.

**Tech Stack:** Jekyll 4.4 + just-the-docs theme v0.12.0 (Ruby/Bundler), which supports 3-level nav via `parent`/`grand_parent` front matter. Markdown for the explainer chapters and landing pages; static HTML/CSS/JS for the course lessons and reference cheatsheets.

## Global Constraints

- **Repo roles:** `speechwave-live/speechwave` (`docs/explainer.md`, `docs/explainer/index.html`) is read-only until Task 5, which deletes both. `learn/elixir` is read-only except for adding `PUBLISHING.md`. `speechwave-live/docs` is the primary write target for this plan.
- **Explainer sanitization is a hard gate.** Task 2 must get Tracy's explicit confirmation before Task 4 (writing the published chapter pages) starts.
- **Back-navigation:** every course page (lessons, reference cheatsheets) gets a back-link to `https://docs.speechwave.live/` in its header. The explainer's chapter pages get this for free since they're real pages inside the just-the-docs nav — no extra work needed there.
- **GitHub link base URL:** `https://github.com/speechwave-live/speechwave/blob/main/` — any repo-relative path mentioned in prose or code comments on a published page becomes a link built from this base.
- **Writing style rules** (from `tmp/writing_docs.md` in the speechwave repo, apply to every touched page, new and existing):
  - Casual-expertise tone: friendly, talented teacher explaining complex topics simply.
  - Simple language, not flowery or dramatic, but still compelling.
  - Avoid AI writing clichés: "not just X, but Y", "the real X is Y", "honestly", "underscores/highlights its importance", "a vital/significant/crucial/pivotal/key role/moment".
  - No em-dashes, en-dashes, or hyphens used to separate phrases.
  - Sentence case for headings and subheadings.
- **Commit format:** conventional commits (`docs:`, `style:`, `chore:`, `fix:`), one commit per task, made in whichever repo that task modifies.
- **No new dependencies:** don't add gems (e.g. html-proofer) to the docs site's `Gemfile`. Verification uses `jekyll build` plus plain shell scripting.

---

### Task 1: Create the "For developers" landing pages

**Files:**
- Create: `speechwave-live/docs/dev.md`
- Create: `speechwave-live/docs/dev/course.md`

**Interfaces:**
- Produces: the URLs `/dev.html` and `/dev/course.html`. `/dev.html` links to `/dev/explainer/index.html` (built in Task 4) and `/dev/course.html` (this task). `/dev/course.html` links to `/dev/course/lessons/*.html` and `/dev/course/reference/*.html` (built in Tasks 6-7). Those targets don't exist yet — that's expected, links will 404 until later tasks land. This task's own build/render check doesn't depend on them.

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

[Read the codebase explainer](/dev/explainer/index.html)

## Elixir for Ruby developers

A short course written while learning Elixir and Phoenix LiveView on the real Speechwave codebase. If you know Ruby and want to get comfortable reading and writing Elixir, start here.

[Start the course](/dev/course.html)
```

- [ ] **Step 2: Write `dev/course.md`**

```markdown
---
title: Elixir course
parent: For developers
nav_order: 2
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

### Task 2: Reconcile explainer content and flag sanitization concerns

**Files:**
- Read: `speechwave-live/speechwave/docs/explainer.md`, `speechwave-live/speechwave/docs/explainer/index.html` (no edits)
- Read: `speechwave-live/speechwave/lib/speechwave/plans.ex`, `lib/speechwave/db_backup.ex`, `lib/speechwave/rate_limiter.ex` (to verify the two topics neither doc covers reliably)
- Create: `speechwave-live/docs/.explainer-notes/*.md` (temporary working notes — not published, deleted in Task 4)
- Modify: `speechwave-live/docs/.gitignore`

**Interfaces:**
- Produces: per-chapter reconciliation notes in `.explainer-notes/`, consumed by Task 4. Also produces Tracy's sanitization confirmation, a hard gate Task 4 cannot start without.

- [ ] **Step 1: Read both sources**

Read `docs/explainer.md` (849 lines) in full. Read `docs/explainer/index.html` chapter by chapter — chapter `<div>`s start at these lines: Overview 402, Data Model 484, Authentication 547, Emoji Journey 656, WebSockets 764, Plans & Limits 825, Supervision Tree 885, DB Backup 937, Chrome Extension 984, Analytics 1056 (file ends around line 1090, before the `<script>` block).

- [ ] **Step 2: Map explainer.md sections onto chapters**

The two sources organize content differently. Use this mapping as your starting point:

| Target chapter | `explainer.md` section(s) | Notes |
|---|---|---|
| Overview | "The big picture", "Project structure" | |
| Data model | "The data model" | |
| Authentication | "Routing" (Public / Requires login / Login itself / OAuth login + connect flows) | explainer.md has no dedicated Authentication heading |
| Emoji journey | "The full emoji journey" | consider folding in "Talk sessions" and "Slide tracking" if they fit; otherwise give them their own chapter |
| WebSockets | "The two websocket connections in detail" (user_socket.ex / endpoint.ex), "Rate limiting" | |
| Plans & limits | none found | verify against `lib/speechwave/plans.ex` and `lib/speechwave/rate_limiter.ex` directly |
| Supervision tree | "Supervision tree" | |
| DB backup | none found | verify against `lib/speechwave/db_backup.ex` directly |
| Chrome extension | "The Chrome extension" | |
| Analytics | "Analytics dashboard" | consider folding in "Dashboard flow" and "LiveView mount and subscription" if they fit; otherwise give them their own chapter |

- [ ] **Step 3: Write reconciliation notes per chapter**

For each of the 10 target chapters (plus any new chapter you decide to split out per Step 2's "otherwise" cases), write a notes file to `.explainer-notes/<chapter-slug>.md` containing: the accurate current facts (favor `explainer.md` over `index.html` wherever they conflict, since `explainer.md` is the actively-maintained one), which `index.html` presentation elements apply (architecture diagram, schema table, stepper walkthrough, callouts, collapsibles) and should carry over, and any code references (file paths) worth linking.

For Plans & limits and DB backup specifically, base the notes on what `lib/speechwave/plans.ex`, `lib/speechwave/db_backup.ex`, and `lib/speechwave/rate_limiter.ex` actually do today, not on either doc.

- [ ] **Step 4: Flag sanitization concerns**

Apply this rubric to everything drafted in Step 3 — flag a passage if it:
- Names specific rate limits, quotas, or anti-abuse thresholds that would help someone game the system (check Plans & limits and Rate limiting content closely).
- Describes auth token generation/verification mechanics beyond a conceptual level, e.g. exact secret derivation, session token format internals (check Authentication content closely).
- Names concrete infrastructure details useful to an attacker: backup file paths/locations, credentials, internal hostnames, non-public admin routes (check DB backup and Supervision tree content closely).
- Reveals unreleased/internal-only roadmap items or business specifics not meant for public view.

Write flagged items (chapter, short quote, reason) to `.explainer-notes/FLAGGED.md`. If nothing is flagged, write that explicitly instead of leaving the file out.

- [ ] **Step 5: Present findings to Tracy**

Send the contents of `.explainer-notes/FLAGGED.md` as a message. Do not proceed to Task 4 until Tracy has explicitly confirmed what to redact, rephrase, or leave as-is.

- [ ] **Step 6: Ignore the notes directory and commit**

```bash
cd /Users/tracy/projects/speechwave-live/docs
echo ".explainer-notes/" >> .gitignore
git add .gitignore
git commit -m "chore: ignore scratch explainer reconciliation notes"
```

---

### Task 3: Extract shared explainer CSS and JS into the docs site

**Files:**
- Create: `speechwave-live/docs/_sass/custom/custom.scss`
- Create: `speechwave-live/docs/assets/js/explainer.js`
- Create: `speechwave-live/docs/_includes/footer_custom.html`

**Interfaces:**
- Produces: CSS classes (`.chapter-eyebrow`, `.chapter-lead`, `.code-block` + syntax spans, `.callout`, `.schema-table`, `.arch-diagram` + node/arrow classes, `.stepper` + sub-classes, `.collapsible` + sub-classes, `.divider`, `.two-col`/`.info-card`) and JS behavior (`initSteppers`, `initCollapsibles`, wired to `DOMContentLoaded`) that Task 4's chapter pages use directly by class name — no further wiring needed once this task is committed.

- [ ] **Step 1: Write `_sass/custom/custom.scss`**

This is `just-the-docs`'s documented custom-CSS extension point (`_includes/css/custom.scss.liquid` already `@import`s `./custom/custom` if present — confirmed present in the installed gem, v0.12.0). It carries over the explainer's content-styling classes from the retired `docs/explainer/index.html`, renamed to avoid colliding with site-wide custom properties, and drops anything that was specific to the old single-page-app shell (top bar, sidebar, chapter show/hide toggle) since just-the-docs now provides that chrome natively.

```scss
// Speechwave codebase explainer — shared styles for chapter pages.
// Ported from the retired docs/explainer/index.html; scoped to
// explainer-only classes so it doesn't affect the rest of the theme.

:root {
  --explainer-bg-dark: #0f172a;
  --explainer-bg-mid: #1e293b;
  --explainer-border: #334155;
  --explainer-accent: #7c3aed;
  --explainer-accent-light: #a78bfa;
  --explainer-accent-dim: #1e1b4b33;
  --explainer-text-bright: #f1f5f9;
  --explainer-text-subtle: #94a3b8;
}

/* Chapter header */
.chapter-eyebrow {
  font-size: 11px;
  font-weight: 600;
  color: var(--explainer-accent);
  text-transform: uppercase;
  letter-spacing: 0.07em;
  margin-bottom: 7px;
}
.chapter-lead {
  font-size: 16px;
  color: #475569;
  line-height: 1.7;
  margin-bottom: 36px;
  max-width: 620px;
}

/* Code blocks */
.code-block {
  background: var(--explainer-bg-dark);
  border: 1px solid var(--explainer-border);
  border-radius: 8px;
  padding: 18px 20px;
  font-family: 'JetBrains Mono', 'Fira Code', 'SF Mono', monospace;
  font-size: 12.5px;
  line-height: 1.75;
  margin: 16px 0 24px;
  overflow-x: auto;
  color: #e2e8f0;
  white-space: pre;
}
.code-block .kw { color: #c084fc; }
.code-block .fn { color: #60a5fa; }
.code-block .str { color: #34d399; }
.code-block .cm { color: #94a3b8; font-style: italic; }
.code-block .at { color: #fbbf24; }
.code-block .num { color: #fb923c; }
.code-block .label { display: block; font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: #475569; margin-bottom: 10px; }

/* Callout */
.callout {
  border-left: 3px solid var(--explainer-accent);
  background: var(--explainer-accent-dim);
  border-radius: 0 8px 8px 0;
  padding: 14px 18px;
  margin: 16px 0 24px;
}
.callout-label {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--explainer-accent);
  letter-spacing: 0.06em;
  margin-bottom: 6px;
}
.callout p { font-size: 13px; color: #475569; margin: 0; line-height: 1.65; }
.callout code { background: #c4b5fd22; }

/* Schema table */
.schema-table { width: 100%; border-collapse: collapse; font-size: 13px; margin: 12px 0 28px; }
.schema-table th {
  background: var(--explainer-bg-dark);
  color: var(--explainer-text-subtle);
  padding: 9px 14px;
  text-align: left;
  font-weight: 600;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.schema-table td { padding: 9px 14px; border-bottom: 1px solid #e2e8f0; color: #334155; vertical-align: top; }
.schema-table tr:last-child td { border-bottom: none; }
.schema-table .field { font-family: monospace; color: var(--explainer-accent); font-size: 12px; }
.schema-table .type { color: #64748b; font-family: monospace; font-size: 11px; }

/* Architecture diagram */
.arch-diagram {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 28px 20px;
  background: var(--explainer-bg-dark);
  border-radius: 10px;
  border: 1px solid var(--explainer-border);
  margin: 16px 0 24px;
  flex-wrap: wrap;
  row-gap: 16px;
}
.arch-node {
  background: var(--explainer-bg-mid);
  border: 1px solid var(--explainer-border);
  border-radius: 8px;
  padding: 12px 18px;
  text-align: center;
  min-width: 110px;
}
.arch-node-emoji { font-size: 22px; display: block; margin-bottom: 4px; }
.arch-node-label { font-size: 11px; font-weight: 600; color: var(--explainer-text-bright); display: block; }
.arch-node-sub { font-size: 10px; color: var(--explainer-text-subtle); display: block; margin-top: 2px; }
.arch-node.highlight { border-color: var(--explainer-accent); background: #1e1b4b; }
.arch-arrow {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 0 10px;
  gap: 2px;
}
.arch-arrow-line { font-size: 18px; color: var(--explainer-accent); line-height: 1; }
.arch-arrow-label { font-size: 9px; color: var(--explainer-text-subtle); text-align: center; max-width: 80px; line-height: 1.3; }

/* Stepper (interactive step-through, used by the Emoji journey chapter) */
.stepper {
  background: var(--explainer-bg-dark);
  border-radius: 10px;
  border: 1px solid var(--explainer-border);
  margin: 20px 0 28px;
  overflow: hidden;
}
.stepper-header {
  padding: 14px 20px;
  border-bottom: 1px solid var(--explainer-border);
  display: flex;
  align-items: center;
  gap: 12px;
}
.stepper-title { font-size: 12px; font-weight: 600; color: var(--explainer-text-subtle); flex: 1; }
.stepper-dots { display: flex; gap: 5px; }
.stepper-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--explainer-border); transition: background 0.2s; }
.stepper-dot.active { background: var(--explainer-accent); }
.stepper-dot.done { background: #4c1d95; }
.stepper-body { padding: 22px 20px 18px; }
.stepper-step { display: none; }
.stepper-step.active { display: block; }
.step-title { font-size: 14px; font-weight: 600; color: var(--explainer-text-bright); margin-bottom: 14px; }
.step-diagram {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 16px;
  flex-wrap: wrap;
  row-gap: 8px;
}
.node {
  background: var(--explainer-bg-mid);
  border: 1px solid var(--explainer-border);
  border-radius: 6px;
  padding: 7px 13px;
  font-size: 11.5px;
  color: #e2e8f0;
  text-align: center;
  transition: opacity 0.2s;
}
.node.active { background: #4c1d95; border-color: var(--explainer-accent); color: white; font-weight: 600; }
.node.dim { opacity: 0.3; }
.arrow { color: var(--explainer-accent); font-size: 15px; flex-shrink: 0; }
.step-desc { font-size: 13px; color: var(--explainer-text-subtle); line-height: 1.7; }
.step-desc code { background: #1e293b; color: var(--explainer-accent-light); }
.stepper-footer {
  padding: 12px 20px;
  border-top: 1px solid var(--explainer-border);
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.step-counter { font-size: 11px; color: #94a3b8; }
.step-btns { display: flex; gap: 8px; }
.btn-step {
  padding: 6px 16px;
  font-size: 12px;
  border-radius: 6px;
  border: none;
  cursor: pointer;
  font-weight: 500;
  transition: background 0.12s;
}
.btn-prev { background: var(--explainer-bg-mid); color: var(--explainer-text-subtle); }
.btn-prev:hover { background: var(--explainer-border); }
.btn-prev:disabled { opacity: 0.4; cursor: default; }
.btn-next { background: var(--explainer-accent); color: white; }
.btn-next:hover { background: #6d28d9; }

/* Collapsible */
.collapsible { border: 1px solid #e2e8f0; border-radius: 8px; margin: 12px 0; overflow: hidden; }
.collapsible-trigger {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  font-size: 13px;
  font-weight: 500;
  color: #334155;
  cursor: pointer;
  background: #f8fafc;
  user-select: none;
}
.collapsible-trigger:hover { background: #f1f5f9; }
.collapsible-icon { font-size: 12px; color: var(--explainer-accent); transition: transform 0.2s; flex-shrink: 0; }
.collapsible.open .collapsible-icon { transform: rotate(90deg); }
.collapsible-body { display: none; padding: 14px 16px; background: white; font-size: 13px; line-height: 1.7; color: #475569; border-top: 1px solid #e2e8f0; }
.collapsible.open .collapsible-body { display: block; }

/* Divider */
.divider { border: none; border-top: 1px solid #e2e8f0; margin: 32px 0; }

/* Two-column info cards */
.two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 16px 0 24px; }
.info-card { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px 18px; }
.info-card-label { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--explainer-accent); margin-bottom: 6px; }
.info-card p { font-size: 12.5px; margin: 0; }

/* Focus styles */
.btn-step:focus-visible { outline: 2px solid var(--explainer-accent); outline-offset: -2px; }
.collapsible-trigger:focus-visible { outline: 2px solid var(--explainer-accent); outline-offset: -2px; }

/* Responsive */
@media (max-width: 700px) {
  .two-col { grid-template-columns: 1fr; }
  .step-diagram { flex-direction: column; align-items: flex-start; }
  .arch-diagram { flex-direction: column; }
  .arch-arrow { flex-direction: row; }
  .arch-arrow-line { transform: rotate(90deg); }
}
```

- [ ] **Step 2: Write `assets/js/explainer.js`**

Adapted from the retired `index.html`'s `initSteppers`/`initCollapsibles` — drops `initNav`, since chapter-to-chapter navigation is now handled by real page loads instead of a JS single-page toggle. Safe to load on every page: it no-ops if there's no `.stepper` or `.collapsible` element on the page.

```javascript
// Speechwave codebase explainer — interactive stepper and collapsible
// sections. Ported from the retired docs/explainer/index.html. No-ops on
// pages with no .stepper or .collapsible elements, so it's safe to load
// site-wide.

function initSteppers() {
  document.querySelectorAll('.stepper').forEach(stepper => {
    const steps = stepper.querySelectorAll('.stepper-step');
    const dotsEl = stepper.querySelector('.stepper-dots');
    const counter = stepper.querySelector('.step-counter');
    const btnPrev = stepper.querySelector('.btn-prev');
    const btnNext = stepper.querySelector('.btn-next');
    let current = 0;

    steps.forEach((_, i) => {
      const dot = document.createElement('div');
      dot.className = 'stepper-dot' + (i === 0 ? ' active' : '');
      dotsEl.appendChild(dot);
    });

    function goTo(n) {
      steps[current].classList.remove('active');
      current = Math.max(0, Math.min(n, steps.length - 1));
      steps[current].classList.add('active');
      dotsEl.querySelectorAll('.stepper-dot').forEach((d, i) => {
        d.classList.toggle('done', i < current);
        d.classList.toggle('active', i === current);
      });
      counter.textContent = `Step ${current + 1} of ${steps.length}`;
      btnPrev.disabled = current === 0;
      btnNext.textContent = current === steps.length - 1 ? '✓ Done' : 'Next →';
    }

    btnPrev.addEventListener('click', () => goTo(current - 1));
    btnNext.addEventListener('click', () => { if (current < steps.length - 1) goTo(current + 1); });
    goTo(0);
  });

  document.addEventListener('keydown', e => {
    const active = document.querySelector('.stepper');
    if (!active) return;
    if (e.key === 'ArrowRight') active.querySelector('.btn-next').click();
    if (e.key === 'ArrowLeft') active.querySelector('.btn-prev').click();
  });
}

function initCollapsibles() {
  document.querySelectorAll('.collapsible').forEach(el => {
    const trigger = el.querySelector('.collapsible-trigger');
    trigger.setAttribute('aria-expanded', 'false');
    trigger.addEventListener('click', () => {
      el.classList.toggle('open');
      trigger.setAttribute('aria-expanded', String(el.classList.contains('open')));
    });
  });
}

document.addEventListener('DOMContentLoaded', () => {
  initSteppers();
  initCollapsibles();
});
```

- [ ] **Step 3: Write `_includes/footer_custom.html`**

This is `just-the-docs`'s documented custom-footer extension point (confirmed present in the installed gem, v0.12.0, currently unused by this site).

```html
<script src="{{ '/assets/js/explainer.js' | relative_url }}"></script>
```

- [ ] **Step 4: Build and confirm the assets are served**

```bash
cd /Users/tracy/projects/speechwave-live/docs
bundle exec jekyll build
test -f _site/assets/js/explainer.js && echo "JS OK"
grep -q "chapter-eyebrow" _site/assets/css/style.css && echo "CSS OK"
```

Expected: both `JS OK` and `CSS OK` print.

- [ ] **Step 5: Commit**

```bash
git add _sass/custom/custom.scss assets/js/explainer.js _includes/footer_custom.html
git commit -m "docs: add shared explainer CSS/JS assets to the docs site"
```

---

### Task 4: Write and publish the explainer chapter pages

**Files:**
- Create: `speechwave-live/docs/dev/explainer/index.md`
- Create: `speechwave-live/docs/dev/explainer/overview.md`
- Create: `speechwave-live/docs/dev/explainer/data-model.md`
- Create: `speechwave-live/docs/dev/explainer/authentication.md`
- Create: `speechwave-live/docs/dev/explainer/emoji-journey.md`
- Create: `speechwave-live/docs/dev/explainer/websockets.md`
- Create: `speechwave-live/docs/dev/explainer/plans-limits.md`
- Create: `speechwave-live/docs/dev/explainer/supervision-tree.md`
- Create: `speechwave-live/docs/dev/explainer/db-backup.md`
- Create: `speechwave-live/docs/dev/explainer/chrome-extension.md`
- Create: `speechwave-live/docs/dev/explainer/analytics.md`
- Create: any additional chapter file Task 2 decided to split out
- Delete: `speechwave-live/docs/.explainer-notes/` (once content is written)

**Interfaces:**
- Consumes: Task 2's reconciliation notes and Tracy's sanitization confirmation (hard gate — do not start this task until Task 2's Step 5 has been confirmed). Consumes Task 3's CSS classes and JS behavior by name.
- Produces: `/dev/explainer/index.html` and `/dev/explainer/*.html`, linked from `/dev.html` (Task 1).

- [ ] **Step 1: Write `dev/explainer/index.md`**

```markdown
---
title: Codebase explainer
parent: For developers
has_children: true
nav_order: 1
---

# Codebase explainer

A guided tour through how Speechwave is built, chapter by chapter.

- [Overview](/dev/explainer/overview.html)
- [Data model](/dev/explainer/data-model.html)
- [Authentication](/dev/explainer/authentication.html)
- [Emoji journey](/dev/explainer/emoji-journey.html)
- [WebSockets](/dev/explainer/websockets.html)
- [Plans and limits](/dev/explainer/plans-limits.html)
- [Supervision tree](/dev/explainer/supervision-tree.html)
- [DB backup](/dev/explainer/db-backup.html)
- [Chrome extension](/dev/explainer/chrome-extension.html)
- [Analytics](/dev/explainer/analytics.html)
```

Add a line for any additional chapter file from Task 2's Step 2 "otherwise" cases.

- [ ] **Step 2: Write each chapter file**

For each chapter, using its `.explainer-notes/<chapter-slug>.md` file from Task 2:

1. Start with front matter:

```markdown
---
title: <Chapter title>
parent: Codebase explainer
grand_parent: For developers
nav_order: <N, matching the index.md list order>
---

# <Chapter title>
```

2. Write the chapter body in markdown, using the CSS classes from Task 3 as raw HTML embedded directly in the markdown file wherever the original `index.html` used them (e.g. `<div class="arch-diagram">...</div>` for the architecture diagram, `<table class="schema-table">...</table>` for schema docs, `<div class="stepper">...</div>` for the Emoji journey's step-through walkthrough, `<div class="callout"><div class="callout-label">Note</div><p>...</p></div>` for callouts). Kramdown (Jekyll's default markdown processor) passes raw HTML blocks through unchanged, so this works directly inside a `.md` file.
3. Apply Global Constraints' GitHub-linking rule: wrap repo-relative paths in links to `https://github.com/speechwave-live/speechwave/blob/main/<path>`.
4. Apply Global Constraints' writing style rules.
5. Apply Task 2's confirmed sanitization redactions/rephrasing for this chapter, if any.

- [ ] **Step 3: Run the automated style checks across all chapter files**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -n "—\|–" dev/explainer/*.md
grep -inE "not just .* but|the real .* is|\bhonestly\b|underscores (its|the)|highlights (its|the)|(vital|significant|crucial|pivotal|key) (role|moment)" dev/explainer/*.md
```

Expected: no matches. Fix and re-run if anything shows up.

- [ ] **Step 4: Build and verify nav, diagrams, and interactivity**

```bash
bundle exec jekyll build
open _site/dev/explainer/index.html
```

Confirm in the browser: the just-the-docs sidebar shows **For developers → Codebase explainer → [each chapter]** three levels deep, the architecture diagram and schema tables render with the intended styling (not raw unstyled HTML), the Emoji journey chapter's stepper responds to clicking Next/Previous, and any collapsible sections open and close.

- [ ] **Step 5: Delete the scratch notes and commit**

```bash
rm -rf .explainer-notes
git add dev/explainer/
git commit -m "docs: publish reconciled codebase explainer chapters"
```

---

### Task 5: Retire the old explainer files and update the README

**Files:**
- Delete: `speechwave-live/speechwave/docs/explainer.md`
- Delete: `speechwave-live/speechwave/docs/explainer/index.html` (and the now-empty `docs/explainer/` directory)
- Modify: `speechwave-live/speechwave/README.md`

**Interfaces:**
- Consumes: Task 4 must be complete and pushed (or at least committed and verified) before this task removes the only remaining copies of the explainer content.

- [ ] **Step 1: Delete the old files**

```bash
cd /Users/tracy/projects/speechwave-live/speechwave
git rm docs/explainer.md
git rm docs/explainer/index.html
rmdir docs/explainer
```

- [ ] **Step 2: Update the README link**

Find this line in `README.md`:

```markdown
For a full explainer on the technical implementation see [this explainer](docs/explainer.md).
```

Replace it with:

```markdown
For a full explainer on the technical implementation see [this explainer](https://docs.speechwave.live/dev/explainer/index.html).
```

- [ ] **Step 3: Verify no other references remain**

```bash
grep -rn "docs/explainer" --include="*.md" . | grep -v "docs/plans/\|docs/specs/"
```

Expected: no output (any remaining hits would be in historical plan/spec documents, which is fine and excluded above).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: retire explainer.md and explainer/index.html, now published at docs.speechwave.live"
```

---

### Task 6: Adapt and publish the reference cheatsheets

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

In each file, wrap any repo-relative code path in a link using the base URL from Global Constraints, same pattern as Task 4.

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

### Task 7: Adapt and publish the course lessons

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

Same CSS and HTML snippet as Task 6 Step 2 — append the `.back-nav` CSS rule to each file's `<style>` block and insert the `<a class="back-nav">` link immediately after `<body>`.

- [ ] **Step 3: Adapt the "open your project" framing to the public repo**

These lessons assume the reader has SpeechWave checked out locally (e.g. "Open your SpeechWave project alongside this lesson. Every example comes from your actual codebase."). Since the repo is now public, reframe these mentions to point at the public GitHub repo instead, e.g.:

```html
<p>Open the <a href="https://github.com/speechwave-live/speechwave">public Speechwave repo</a> alongside this lesson, or follow the file links below &mdash; every example comes from the real codebase.</p>
```

Adjust wording per-lesson to fit context; don't do a blind find-replace since the surrounding sentence varies lesson to lesson.

- [ ] **Step 4: Replace repo-relative paths with GitHub links**

Same pattern as Task 4 and Task 6 Step 3 — wrap file paths in links to `https://github.com/speechwave-live/speechwave/blob/main/<path>`.

- [ ] **Step 5: Apply the writing style pass**

Read each of the 9 lessons and edit prose per the Global Constraints style rules. Be careful editing inside the quiz `<script>` blocks — only touch visible prose/labels, not the JS logic that checks answers.

- [ ] **Step 6: Run the automated style checks across all 9 files**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -n "—\|–" dev/course/lessons/*.html
grep -inE "not just .* but|the real .* is|\bhonestly\b|underscores (its|the)|highlights (its|the)|(vital|significant|crucial|pivotal|key) (role|moment)" dev/course/lessons/*.html
```

Expected: no matches. Fix and re-run if anything shows up.

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

### Task 8: Apply the writing style pass to existing onboarding pages

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

### Task 9: Write the repeatable course-publishing checklist

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

### Task 10: Final full-site verification

**Files:**
- None created or modified — verification only. Fix-up commits go in whichever repo/file the issue is found in.

**Interfaces:**
- Consumes: every file created/modified in Tasks 1-8.

- [ ] **Step 1: Full build**

```bash
cd /Users/tracy/projects/speechwave-live/docs
bundle exec jekyll build
```

Expected: build succeeds with no errors or warnings about missing files.

- [ ] **Step 2: Check the 3-level nav**

```bash
open _site/dev.html
```

Confirm the sidebar shows: **For developers** (top level) containing **Codebase explainer** (with all chapter pages nested under it) and **Elixir course**.

- [ ] **Step 3: Confirm the reconciliation deltas made it into the published chapters**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -il "presence" dev/explainer/*.md
grep -il "auththrottle\|auth throttle" dev/explainer/*.md
grep -il "dashboard" dev/explainer/*.md
grep -il "polling" dev/explainer/*.md
```

Expected: each command prints at least one filename. These are the specific architecture changes identified in Task 2 as missing from the old `index.html` — if any of these greps come back empty, the corresponding chapter is still missing content from `explainer.md` and needs another pass.

- [ ] **Step 4: Check internal links resolve**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -rho 'href="/dev[^"]*"' dev.md dev/course.md dev/explainer/index.md | sed 's/href="//;s/"$//' | while read -r path; do
  file="_site${path}"
  if [ ! -f "$file" ]; then
    echo "MISSING: $path"
  fi
done
```

Expected: no output (every internal `/dev/...` link has a matching built file). Fix any `MISSING` results before continuing.

- [ ] **Step 5: Check external GitHub links resolve**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -rhoE 'https://github\.com/speechwave-live/speechwave[^"]*' dev/explainer/*.md dev/course/lessons/*.html dev/course/reference/*.html | sort -u | while read -r url; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  if [ "$code" != "200" ]; then
    echo "BROKEN ($code): $url"
  fi
done
```

Expected: no output. Fix any `BROKEN` results (typo'd path, renamed file) before continuing.

- [ ] **Step 6: Re-run the full style-rule grep across every touched file**

```bash
cd /Users/tracy/projects/speechwave-live/docs
grep -n "—\|–" dev.md dev/course.md dev/explainer/*.md dev/course/lessons/*.html dev/course/reference/*.html index.md getting-started.md dashboard.md extension.md troubleshooting.md
```

Expected: no matches.

- [ ] **Step 7: Confirm the old explainer files are gone**

```bash
cd /Users/tracy/projects/speechwave-live/speechwave
test ! -e docs/explainer.md && test ! -e docs/explainer && echo "OK: old explainer files removed"
grep -q "docs.speechwave.live/dev/explainer" README.md && echo "OK: README updated"
```

Expected: both `OK` lines print.

- [ ] **Step 8: Manual spot-check**

Open `_site/dev.html`, `_site/dev/course.html`, one explainer chapter, one lesson, and one reference page in a browser. Confirm: navigation between explainer chapters uses the just-the-docs sidebar correctly, the course landing page links out correctly, and every course page's back-link returns to `https://docs.speechwave.live/`.

- [ ] **Step 9: Push**

Once everything above passes, ask Tracy whether to push the `speechwave-live/docs`, `speechwave-live/speechwave`, and `learn/elixir` commits to their remotes (this plan does not push automatically).
