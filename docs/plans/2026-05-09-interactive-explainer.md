# Interactive Codebase Explainer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `docs/explainer/index.html` — a fully self-contained, interactive HTML guide covering all current Speechwave architecture, schemas, and flows (including the new auth, plans, and DB backup systems).

**Architecture:** Single HTML file with all CSS and JS inlined. Sidebar navigation toggles chapter `<div>`s via vanilla JS. Key flows use a step-by-step stepper component built with data attributes and event delegation. No external dependencies, no build step.

**Tech Stack:** HTML5, CSS custom properties, vanilla ES2020 JS (inlined). No framework, no CDN, no build tooling.

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `docs/explainer/index.html` | Create | Single output — all CSS, JS, and content inlined |
| `docs/explainer.md` | Keep for now | Remove after HTML version is complete and reviewed |

All tasks modify only `docs/explainer/index.html`. Each task adds or fills in a section of the same file.

---

## Task 1: HTML Skeleton — Shell, CSS, and JS

**Files:**
- Create: `docs/explainer/index.html`

This task creates the complete structural shell: the top bar, sidebar nav (all items), empty chapter `<div>`s, all CSS, and all JS. No chapter content yet — just the frame that everything else clicks into.

- [ ] **Step 1.1: Create the file with complete shell**

Write `docs/explainer/index.html` with this exact content:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Speechwave — Codebase Guide</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --bg-dark: #0f172a;
  --bg-mid: #1e293b;
  --bg-light: #f8fafc;
  --border: #334155;
  --accent: #7c3aed;
  --accent-light: #a78bfa;
  --accent-dim: #1e1b4b33;
  --text-bright: #f1f5f9;
  --text-main: #1e293b;
  --text-muted: #64748b;
  --text-subtle: #94a3b8;
  --green: #34d399;
  --blue: #60a5fa;
  --yellow: #fbbf24;
}
html, body { height: 100%; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background: var(--bg-light);
  color: var(--text-main);
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
}

/* ── Top bar ── */
.top-bar {
  background: var(--bg-dark);
  color: white;
  padding: 10px 20px;
  display: flex;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
  border-bottom: 1px solid var(--border);
}
.top-bar-logo { font-size: 14px; font-weight: 700; color: var(--accent-light); letter-spacing: -0.02em; }
.top-bar-sep { color: #334155; }
.top-bar-subtitle { font-size: 13px; color: var(--text-subtle); }

/* ── Shell ── */
.shell { display: flex; flex: 1; overflow: hidden; }

/* ── Sidebar ── */
.sidebar {
  width: 220px;
  flex-shrink: 0;
  background: var(--bg-dark);
  border-right: 1px solid var(--border);
  overflow-y: auto;
  padding: 14px 0 24px;
}
.sidebar-section {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: #475569;
  padding: 0 16px;
  margin: 16px 0 6px;
}
.sidebar-section:first-child { margin-top: 4px; }
.nav-item {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 8px 16px;
  font-size: 12.5px;
  color: var(--text-subtle);
  cursor: pointer;
  border-left: 2px solid transparent;
  transition: color 0.12s, background 0.12s;
  user-select: none;
}
.nav-item:hover { color: var(--text-bright); background: var(--bg-mid); }
.nav-item.active { color: var(--accent-light); border-left-color: var(--accent); background: var(--accent-dim); font-weight: 500; }
.nav-item .icon { font-size: 14px; flex-shrink: 0; line-height: 1; }
.nav-badge {
  margin-left: auto;
  font-size: 9px;
  font-weight: 700;
  background: #4c1d9533;
  color: var(--accent-light);
  border-radius: 3px;
  padding: 1px 5px;
  letter-spacing: 0.02em;
}

/* ── Main content ── */
.main { flex: 1; overflow-y: auto; }
.chapter { display: none; }
.chapter.active { display: block; }
.content { max-width: 780px; margin: 0 auto; padding: 40px 48px 80px; }

/* ── Chapter header ── */
.chapter-eyebrow {
  font-size: 11px;
  font-weight: 600;
  color: var(--accent);
  text-transform: uppercase;
  letter-spacing: 0.07em;
  margin-bottom: 7px;
}
.chapter-title {
  font-size: 28px;
  font-weight: 700;
  color: var(--text-main);
  letter-spacing: -0.025em;
  margin-bottom: 12px;
  line-height: 1.2;
}
.chapter-lead {
  font-size: 16px;
  color: #475569;
  line-height: 1.7;
  margin-bottom: 36px;
  max-width: 620px;
}
h3 {
  font-size: 17px;
  font-weight: 600;
  color: var(--text-main);
  margin: 32px 0 10px;
  letter-spacing: -0.01em;
}
h4 {
  font-size: 13px;
  font-weight: 600;
  color: #334155;
  margin: 20px 0 8px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
p { font-size: 14px; line-height: 1.75; color: #334155; margin-bottom: 12px; }
ul, ol { padding-left: 20px; margin-bottom: 12px; }
li { font-size: 14px; line-height: 1.75; color: #334155; }
code {
  font-family: 'JetBrains Mono', 'Fira Code', 'SF Mono', monospace;
  font-size: 12px;
  background: #e2e8f0;
  padding: 1px 5px;
  border-radius: 3px;
  color: var(--accent);
}

/* ── Code blocks ── */
.code-block {
  background: var(--bg-dark);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 18px 20px;
  font-family: 'JetBrains Mono', 'Fira Code', 'SF Mono', monospace;
  font-size: 12.5px;
  line-height: 1.75;
  margin: 16px 0 24px;
  overflow-x: auto;
  color: #e2e8f0;
}
.code-block .kw { color: #c084fc; }
.code-block .fn { color: #60a5fa; }
.code-block .str { color: #34d399; }
.code-block .cm { color: #475569; font-style: italic; }
.code-block .at { color: #fbbf24; }
.code-block .num { color: #fb923c; }
.code-block .label { display: block; font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: #475569; margin-bottom: 10px; }

/* ── Callout ── */
.callout {
  border-left: 3px solid var(--accent);
  background: var(--accent-dim);
  border-radius: 0 8px 8px 0;
  padding: 14px 18px;
  margin: 16px 0 24px;
}
.callout-label {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--accent);
  letter-spacing: 0.06em;
  margin-bottom: 6px;
}
.callout p { font-size: 13px; color: #475569; margin: 0; line-height: 1.65; }
.callout code { background: #c4b5fd22; }

/* ── Schema table ── */
.schema-table { width: 100%; border-collapse: collapse; font-size: 13px; margin: 12px 0 28px; }
.schema-table th {
  background: var(--bg-dark);
  color: var(--text-subtle);
  padding: 9px 14px;
  text-align: left;
  font-weight: 600;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.schema-table td { padding: 9px 14px; border-bottom: 1px solid #e2e8f0; color: #334155; vertical-align: top; }
.schema-table tr:last-child td { border-bottom: none; }
.schema-table .field { font-family: monospace; color: var(--accent); font-size: 12px; }
.schema-table .type { color: var(--text-muted); font-family: monospace; font-size: 11px; }

/* ── Arch diagram ── */
.arch-diagram {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0;
  padding: 28px 20px;
  background: var(--bg-dark);
  border-radius: 10px;
  border: 1px solid var(--border);
  margin: 16px 0 24px;
  flex-wrap: wrap;
  row-gap: 16px;
}
.arch-node {
  background: var(--bg-mid);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 12px 18px;
  text-align: center;
  min-width: 110px;
}
.arch-node-emoji { font-size: 22px; display: block; margin-bottom: 4px; }
.arch-node-label { font-size: 11px; font-weight: 600; color: var(--text-bright); display: block; }
.arch-node-sub { font-size: 10px; color: var(--text-subtle); display: block; margin-top: 2px; }
.arch-node.highlight { border-color: var(--accent); background: #1e1b4b; }
.arch-arrow {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 0 10px;
  gap: 2px;
}
.arch-arrow-line { font-size: 18px; color: var(--accent); line-height: 1; }
.arch-arrow-label { font-size: 9px; color: var(--text-subtle); text-align: center; max-width: 80px; line-height: 1.3; }

/* ── Stepper ── */
.stepper {
  background: var(--bg-dark);
  border-radius: 10px;
  border: 1px solid var(--border);
  margin: 20px 0 28px;
  overflow: hidden;
}
.stepper-header {
  padding: 14px 20px;
  border-bottom: 1px solid var(--border);
  display: flex;
  align-items: center;
  gap: 12px;
}
.stepper-title { font-size: 12px; font-weight: 600; color: var(--text-subtle); flex: 1; }
.stepper-dots { display: flex; gap: 5px; }
.stepper-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--border); transition: background 0.2s; }
.stepper-dot.active { background: var(--accent); }
.stepper-dot.done { background: #4c1d95; }
.stepper-body { padding: 22px 20px 18px; }
.stepper-step { display: none; }
.stepper-step.active { display: block; }
.step-title { font-size: 14px; font-weight: 600; color: var(--text-bright); margin-bottom: 14px; }
.step-diagram {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 16px;
  flex-wrap: wrap;
  row-gap: 8px;
}
.node {
  background: var(--bg-mid);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 7px 13px;
  font-size: 11.5px;
  color: #e2e8f0;
  text-align: center;
  transition: opacity 0.2s;
}
.node.active { background: #4c1d95; border-color: var(--accent); color: white; font-weight: 600; }
.node.dim { opacity: 0.3; }
.arrow { color: var(--accent); font-size: 15px; flex-shrink: 0; }
.step-desc { font-size: 13px; color: var(--text-subtle); line-height: 1.7; }
.step-desc code { background: #1e293b; color: var(--accent-light); }
.stepper-footer {
  padding: 12px 20px;
  border-top: 1px solid var(--border);
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.step-counter { font-size: 11px; color: #475569; }
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
.btn-prev { background: var(--bg-mid); color: var(--text-subtle); }
.btn-prev:hover { background: var(--border); }
.btn-next { background: var(--accent); color: white; }
.btn-next:hover { background: #6d28d9; }

/* ── Collapsible ── */
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
.collapsible-icon { font-size: 12px; color: var(--accent); transition: transform 0.2s; flex-shrink: 0; }
.collapsible.open .collapsible-icon { transform: rotate(90deg); }
.collapsible-body { display: none; padding: 14px 16px; background: white; font-size: 13px; line-height: 1.7; color: #475569; border-top: 1px solid #e2e8f0; }
.collapsible.open .collapsible-body { display: block; }

/* ── Divider ── */
.divider { border: none; border-top: 1px solid #e2e8f0; margin: 32px 0; }

/* ── Two-col ── */
.two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 16px 0 24px; }
.info-card { background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px 18px; }
.info-card-label { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); margin-bottom: 6px; }
.info-card p { font-size: 12.5px; margin: 0; }
</style>
</head>
<body>

<header class="top-bar">
  <span class="top-bar-logo">Speechwave</span>
  <span class="top-bar-sep">/</span>
  <span class="top-bar-subtitle">Codebase Guide</span>
</header>

<div class="shell">
  <nav class="sidebar">
    <div class="sidebar-section">Getting Started</div>
    <div class="nav-item active" data-chapter="overview"><span class="icon">🗺️</span> Overview</div>
    <div class="nav-item" data-chapter="data-model"><span class="icon">🗄️</span> Data Model</div>

    <div class="sidebar-section">Key Flows</div>
    <div class="nav-item" data-chapter="authentication"><span class="icon">🔐</span> Authentication <span class="nav-badge">new</span></div>
    <div class="nav-item" data-chapter="emoji-journey"><span class="icon">🔥</span> Emoji Journey</div>
    <div class="nav-item" data-chapter="websockets"><span class="icon">🔌</span> WebSockets</div>

    <div class="sidebar-section">Infrastructure</div>
    <div class="nav-item" data-chapter="plans"><span class="icon">💳</span> Plans &amp; Limits <span class="nav-badge">new</span></div>
    <div class="nav-item" data-chapter="supervision"><span class="icon">🌳</span> Supervision Tree</div>
    <div class="nav-item" data-chapter="db-backup"><span class="icon">💾</span> DB Backup <span class="nav-badge">new</span></div>

    <div class="sidebar-section">Features</div>
    <div class="nav-item" data-chapter="chrome-extension"><span class="icon">💻</span> Chrome Extension</div>
    <div class="nav-item" data-chapter="analytics"><span class="icon">📊</span> Analytics</div>
  </nav>

  <main class="main">
    <div id="chapter-overview" class="chapter active">
      <div class="content"><!-- Task 2 fills this --></div>
    </div>
    <div id="chapter-data-model" class="chapter">
      <div class="content"><!-- Task 3 fills this --></div>
    </div>
    <div id="chapter-authentication" class="chapter">
      <div class="content"><!-- Task 4 fills this --></div>
    </div>
    <div id="chapter-emoji-journey" class="chapter">
      <div class="content"><!-- Task 5 fills this --></div>
    </div>
    <div id="chapter-websockets" class="chapter">
      <div class="content"><!-- Task 6 fills this --></div>
    </div>
    <div id="chapter-plans" class="chapter">
      <div class="content"><!-- Task 7 fills this --></div>
    </div>
    <div id="chapter-supervision" class="chapter">
      <div class="content"><!-- Task 8 fills this --></div>
    </div>
    <div id="chapter-db-backup" class="chapter">
      <div class="content"><!-- Task 9 fills this --></div>
    </div>
    <div id="chapter-chrome-extension" class="chapter">
      <div class="content"><!-- Task 10 fills this --></div>
    </div>
    <div id="chapter-analytics" class="chapter">
      <div class="content"><!-- Task 11 fills this --></div>
    </div>
  </main>
</div>

<script>
// ── Chapter navigation ──────────────────────────────────────────────────────
function initNav() {
  const items = document.querySelectorAll('.nav-item[data-chapter]');
  items.forEach(item => {
    item.addEventListener('click', () => {
      const id = item.dataset.chapter;
      // Deactivate all
      items.forEach(i => i.classList.remove('active'));
      document.querySelectorAll('.chapter').forEach(c => c.classList.remove('active'));
      // Activate selected
      item.classList.add('active');
      document.getElementById('chapter-' + id).classList.add('active');
      document.querySelector('.main').scrollTo(0, 0);
    });
  });
}

// ── Step stepper ────────────────────────────────────────────────────────────
function initSteppers() {
  document.querySelectorAll('.stepper').forEach(stepper => {
    const steps = stepper.querySelectorAll('.stepper-step');
    const dotsEl = stepper.querySelector('.stepper-dots');
    const counter = stepper.querySelector('.step-counter');
    const btnPrev = stepper.querySelector('.btn-prev');
    const btnNext = stepper.querySelector('.btn-next');
    let current = 0;

    // Build dots
    steps.forEach((_, i) => {
      const dot = document.createElement('div');
      dot.className = 'stepper-dot' + (i === 0 ? ' active' : '');
      dotsEl.appendChild(dot);
    });

    function goTo(n) {
      steps[current].classList.remove('active');
      current = Math.max(0, Math.min(n, steps.length - 1));
      steps[current].classList.add('active');
      // Update dots
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

  // Keyboard: arrow keys when stepper is focused
  document.addEventListener('keydown', e => {
    const active = document.querySelector('.chapter.active .stepper');
    if (!active) return;
    if (e.key === 'ArrowRight') active.querySelector('.btn-next').click();
    if (e.key === 'ArrowLeft') active.querySelector('.btn-prev').click();
  });
}

// ── Collapsibles ────────────────────────────────────────────────────────────
function initCollapsibles() {
  document.querySelectorAll('.collapsible').forEach(el => {
    el.querySelector('.collapsible-trigger').addEventListener('click', () => {
      el.classList.toggle('open');
    });
  });
}

document.addEventListener('DOMContentLoaded', () => {
  initNav();
  initSteppers();
  initCollapsibles();
});
</script>

</body>
</html>
```

- [ ] **Step 1.2: Verify structure in browser**

Open `docs/explainer/index.html` in a browser. Verify:
- Top bar shows "Speechwave / Codebase Guide"
- Sidebar shows all 10 nav items with correct section headers
- Three items have "new" badges: Authentication, Plans & Limits, DB Backup
- Clicking any nav item switches the active highlight (content areas are empty — that's expected)
- No console errors

- [ ] **Step 1.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "feat: add interactive explainer skeleton"
```

---

## Task 2: Overview Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-overview .content`

The Overview introduces the three actors, two WebSocket connections, and current file tree. Replace `<!-- Task 2 fills this -->` inside `#chapter-overview .content`.

- [ ] **Step 2.1: Fill the Overview chapter**

Replace the comment placeholder inside `<div id="chapter-overview" class="chapter active"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 1</div>
<h1 class="chapter-title">Overview</h1>
<p class="chapter-lead">Speechwave lets conference attendees send live emoji reactions that float up on the speaker's screen in real time. Three actors, two WebSocket connections, one PubSub bus tying it all together.</p>

<h3>The Three Actors</h3>
<div class="arch-diagram">
  <div class="arch-node">
    <span class="arch-node-emoji">📱</span>
    <span class="arch-node-label">Attendee</span>
    <span class="arch-node-sub">opens /t/:slug, taps emoji</span>
  </div>
  <div class="arch-arrow">
    <span class="arch-arrow-line">→</span>
    <span class="arch-arrow-label">LiveView WebSocket /live</span>
  </div>
  <div class="arch-node highlight">
    <span class="arch-node-emoji">⚡</span>
    <span class="arch-node-label">Phoenix Server</span>
    <span class="arch-node-sub">rate-limits & broadcasts</span>
  </div>
  <div class="arch-arrow">
    <span class="arch-arrow-line">→</span>
    <span class="arch-arrow-label">Channel WebSocket /socket</span>
  </div>
  <div class="arch-node">
    <span class="arch-node-emoji">💻</span>
    <span class="arch-node-label">Speaker</span>
    <span class="arch-node-sub">Chrome extension on laptop</span>
  </div>
</div>

<p>Two different WebSocket connections are in play:</p>
<table class="schema-table">
  <thead><tr><th>Connection</th><th>Path</th><th>Protocol</th><th>Used by</th></tr></thead>
  <tbody>
    <tr><td class="field">/live</td><td class="type">Phoenix LiveView</td><td>Managed automatically</td><td>Attendee browser</td></tr>
    <tr><td class="field">/socket</td><td class="type">Phoenix Channel</td><td>Manual connect + join</td><td>Chrome extension</td></tr>
  </tbody>
</table>

<h3>Project File Tree</h3>
<div class="code-block"><span class="cm">lib/
  speechwave/
    application.ex              OTP supervision tree
    accounts.ex                 User auth context (magic links, OAuth, API keys)
    accounts/
      user.ex                   User schema (email, plan, api_key, is_admin)
      user_identity.ex          OAuth identity (provider + uid, one per account)
      user_token.ex             Session + magic-link tokens
      scope.ex                  Scope struct wrapping authenticated user
      user_notifier.ex          Email delivery (magic link, email change)
    talks.ex                    Talk + session context (CRUD, lifecycle)
    talks/talk.ex               Talk schema (belongs_to user)
    talks/talk_session.ex       TalkSession schema
    reactions.ex                Reactions context (create, totals query)
    reactions/reaction.ex       Reaction schema
    rate_limiter.ex             GenServer + ETS rate limiting
    plans.ex                    Tier limits (free / pro / org)
    qr_code.ex                  QR code generation
    db_backup.ex                Hourly SQLite backup to S3 (GenServer)
  speechwave_web/
    live/
      talk_live.ex              Attendee reaction page (LiveView)
      dashboard_live.ex         Speaker dashboard: talks, sessions, QR codes
      session_analytics_live.ex Per-session analytics
      user_live/login.ex        Magic link + OAuth login page
      user_live/settings.ex     Email change + connected accounts
    channels/
      user_socket.ex            Socket definition (API-key auth)
      reaction_channel.ex       Channel: reactions, sessions, slide_changed
    controllers/
      user_session_controller.ex Magic link click + OAuth callback
    presence.ex                 Tracks attendees per talk (plan enforcement)
    router.ex                   Route definitions
    user_auth.ex                Auth plugs + LiveView on_mount hooks</span></div>

<div class="callout">
  <div class="callout-label">What changed from older versions?</div>
  <p>Admin HTTP Basic Auth is gone. Talks are now owned by registered users (not a global admin). Authentication is passwordless — magic links and OAuth only. Three new systems: <code>Plans</code> for tier enforcement, <code>Presence</code> for participant counting, and <code>DbBackup</code> for hourly SQLite snapshots.</p>
</div>
```

- [ ] **Step 2.2: Verify in browser**

Reload `docs/explainer/index.html`. The Overview chapter should show the architecture diagram with three nodes and arrows, the two-connection table, and the annotated file tree. Check that the callout box renders with a purple left border.

- [ ] **Step 2.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add Overview chapter to explainer"
```

---

## Task 3: Data Model Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-data-model .content`

Five schemas, each shown as an annotated table. Replace the comment placeholder inside `#chapter-data-model .content`.

- [ ] **Step 3.1: Fill the Data Model chapter**

Replace the comment inside `<div id="chapter-data-model" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 2</div>
<h1 class="chapter-title">Data Model</h1>
<p class="chapter-lead">Five database tables. The slug on <code>talks</code> is the key that ties all three actors together — it appears in the URL, the PubSub topic, and the Channel topic.</p>

<h3>users</h3>
<p>One row per registered speaker. Created automatically on first login (magic link or OAuth).</p>
<table class="schema-table">
  <thead><tr><th>Field</th><th>Type</th><th>Notes</th></tr></thead>
  <tbody>
    <tr><td class="field">email</td><td class="type">:string</td><td>Lowercased, unique. The primary identity.</td></tr>
    <tr><td class="field">plan</td><td class="type">:enum</td><td><code>:free</code> | <code>:pro</code> | <code>:org</code>. Defaults to <code>:free</code>. Drives limits in the Plans module.</td></tr>
    <tr><td class="field">api_key</td><td class="type">:string</td><td>32-byte hex token. Auto-generated on insert. Used by the Chrome extension to authenticate on Channel join.</td></tr>
    <tr><td class="field">is_admin</td><td class="type">:boolean</td><td>Staff flag. Defaults false. Not tied to route-level auth.</td></tr>
    <tr><td class="field">authenticated_at</td><td class="type">:utc_datetime (virtual)</td><td>Set when a session token is verified. Used for sudo-mode checks (20-minute window).</td></tr>
  </tbody>
</table>

<h3>user_identities</h3>
<p>One row per OAuth provider account. A single user can have multiple identities (e.g. Google + GitHub).</p>
<table class="schema-table">
  <thead><tr><th>Field</th><th>Type</th><th>Notes</th></tr></thead>
  <tbody>
    <tr><td class="field">provider</td><td class="type">:string</td><td><code>"google"</code>, <code>"github"</code>, or <code>"microsoft"</code></td></tr>
    <tr><td class="field">uid</td><td class="type">:string</td><td>The <code>sub</code> claim from the OAuth provider. Stable unique ID.</td></tr>
    <tr><td class="field">user_id</td><td class="type">:integer</td><td>Foreign key → users. <code>unique_constraint([:provider, :uid])</code> prevents duplicate links.</td></tr>
  </tbody>
</table>

<h3>talks</h3>
<p>One row per presentation. A speaker creates talks in the dashboard; each gets a unique slug used in the audience URL.</p>
<table class="schema-table">
  <thead><tr><th>Field</th><th>Type</th><th>Notes</th></tr></thead>
  <tbody>
    <tr><td class="field">title</td><td class="type">:string</td><td>Human-readable name, e.g. "My Conference Talk"</td></tr>
    <tr><td class="field">slug</td><td class="type">:string</td><td>URL-safe key, e.g. <code>"my-conference-talk"</code>. Auto-generated from title; unique across all talks.</td></tr>
    <tr><td class="field">user_id</td><td class="type">:integer</td><td>Foreign key → users. All Talks queries that touch user data require a <code>Scope</code> struct and filter by this field.</td></tr>
  </tbody>
</table>

<h3>talk_sessions</h3>
<p>A recording window within a talk — the span of time during which reactions are persisted. Start/stop controlled by the speaker via the Chrome extension or dashboard.</p>
<table class="schema-table">
  <thead><tr><th>Field</th><th>Type</th><th>Notes</th></tr></thead>
  <tbody>
    <tr><td class="field">label</td><td class="type">:string</td><td>Auto-increments ("Session 1", "Session 2", …). Speaker can rename from the dashboard.</td></tr>
    <tr><td class="field">started_at</td><td class="type">:utc_datetime</td><td>Set when <code>start_session/1</code> is called.</td></tr>
    <tr><td class="field">ended_at</td><td class="type">:utc_datetime</td><td><code>nil</code> while active. <code>get_active_session/1</code> queries for <code>IS NULL</code>.</td></tr>
    <tr><td class="field">talk_id</td><td class="type">:integer</td><td>Foreign key → talks.</td></tr>
  </tbody>
</table>

<h3>reactions</h3>
<p>One row per emoji tap. Only persisted when a session is active.</p>
<table class="schema-table">
  <thead><tr><th>Field</th><th>Type</th><th>Notes</th></tr></thead>
  <tbody>
    <tr><td class="field">emoji</td><td class="type">:string</td><td>One of the 9 emojis: ❤️ 😂 👏 🤯 🙋🏻 🎉 💩 😮 🎯</td></tr>
    <tr><td class="field">slide_number</td><td class="type">:integer</td><td>Current slide when the tap happened. <code>0</code> means unknown (no adapter or pre-session). Analytics groups slide-0 reactions under "General".</td></tr>
    <tr><td class="field">talk_session_id</td><td class="type">:integer</td><td>Foreign key → talk_sessions. Cascades delete when session is deleted.</td></tr>
  </tbody>
</table>
```

- [ ] **Step 3.2: Verify in browser**

Click "Data Model" in the sidebar. Five schema tables should render with purple field names, monospace type labels, and readable notes. The `users` table should have 5 rows.

- [ ] **Step 3.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add Data Model chapter to explainer"
```

---

## Task 4: Authentication Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-authentication .content`

The most-changed part of the codebase. Covers magic links, OAuth (Assent), Scope, API key, and sudo mode. Uses a stepper for the magic link flow.

- [ ] **Step 4.1: Fill the Authentication chapter**

Replace the comment inside `<div id="chapter-authentication" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 3 — New</div>
<h1 class="chapter-title">Authentication</h1>
<p class="chapter-lead">Speechwave is passwordless. Speakers sign in via magic link or OAuth (Google, GitHub, Microsoft). No passwords are stored. The Chrome extension authenticates with a per-user API key.</p>

<div class="two-col">
  <div class="info-card">
    <div class="info-card-label">Magic Link</div>
    <p>User enters email → server emails a one-time token → user clicks link → session created. Token is deleted on use.</p>
  </div>
  <div class="info-card">
    <div class="info-card-label">OAuth (Assent)</div>
    <p>User clicks provider button → redirected to Google/GitHub/Microsoft → callback creates or finds user by email → session created.</p>
  </div>
</div>

<h3>Magic Link Flow</h3>
<div class="stepper">
  <div class="stepper-header">
    <span class="stepper-title">Magic Link — step by step</span>
    <div class="stepper-dots"></div>
  </div>
  <div class="stepper-body">
    <div class="stepper-step">
      <div class="step-title">Step 1 — User submits email on /users/log-in</div>
      <div class="step-diagram">
        <div class="node active">📱 Browser</div>
        <div class="arrow">→</div>
        <div class="node">UserLive.Login</div>
        <div class="arrow">→</div>
        <div class="node">handle_event "submit_magic"</div>
      </div>
      <div class="step-desc"><code>register_or_get_user_by_email/1</code> finds an existing user or inserts a new one. Either way, a magic link is always sent — the response never reveals whether the account existed. This prevents user enumeration.</div>
    </div>
    <div class="stepper-step">
      <div class="step-title">Step 2 — Server creates a UserToken and emails the link</div>
      <div class="step-diagram">
        <div class="node dim">📱 Browser</div>
        <div class="arrow">→</div>
        <div class="node active">Accounts context</div>
        <div class="arrow">→</div>
        <div class="node">UserToken (type: "login")</div>
        <div class="arrow">→</div>
        <div class="node">Swoosh email</div>
      </div>
      <div class="step-desc"><code>deliver_login_instructions/2</code> builds a signed token via <code>UserToken.build_email_token/2</code>, inserts it in <code>user_tokens</code>, and sends the magic link email. The token expires in 15 minutes.</div>
    </div>
    <div class="stepper-step">
      <div class="step-title">Step 3 — User clicks the link in their inbox</div>
      <div class="step-diagram">
        <div class="node dim">📱 Email client</div>
        <div class="arrow">→</div>
        <div class="node active">GET /users/magic_link/:token</div>
        <div class="arrow">→</div>
        <div class="node">UserSessionController</div>
      </div>
      <div class="step-desc">The controller calls <code>login_user_by_magic_link/1</code>. If the token is valid, the token record is deleted (single-use) and <code>UserAuth.log_in_user/2</code> creates a session.</div>
    </div>
    <div class="stepper-step">
      <div class="step-title">Step 4 — Session created, user redirected to dashboard</div>
      <div class="step-diagram">
        <div class="node active">Session token</div>
        <div class="arrow">→</div>
        <div class="node">user_tokens (context: "session")</div>
        <div class="arrow">→</div>
        <div class="node">redirect /dashboard</div>
      </div>
      <div class="step-desc"><code>log_in_user/2</code> generates a session token via <code>generate_user_session_token/1</code>, stores it in the browser session cookie, and redirects. The session is verified on every request by the <code>:fetch_current_scope_for_user</code> plug.</div>
    </div>
  </div>
  <div class="stepper-footer">
    <span class="step-counter"></span>
    <div class="step-btns">
      <button class="btn-step btn-prev">← Prev</button>
      <button class="btn-step btn-next">Next →</button>
    </div>
  </div>
</div>

<h3>OAuth Flow (Assent)</h3>
<p>Clicking a provider button hits <code>GET /auth/:provider</code>. The controller uses the Assent library to build an authorization URL and redirect. On return, <code>GET /auth/:provider/callback</code> exchanges the code for user info.</p>
<p>There are two contexts for OAuth, determined by whether a user is already logged in:</p>
<ul>
  <li><strong>Login context</strong> — calls <code>find_or_create_user_from_oauth/2</code>. Looks up existing <code>UserIdentity</code> by <code>{provider, uid}</code>. If not found, upserts the user by email and inserts a new identity.</li>
  <li><strong>Connect context</strong> — user is already logged in (visiting Settings). Links a new OAuth provider to their existing account via <code>link_identity_to_user/3</code>.</li>
</ul>
<div class="callout">
  <div class="callout-label">Email verification guard</div>
  <p>OAuth login requires <code>email_verified: true</code> in the provider's user info. A missing or <code>false</code> value returns <code>{:error, :email_not_verified}</code>. This prevents OAuth providers from assigning someone else's unverified email to a new account.</p>
</div>

<h3>The Scope Struct</h3>
<p>Every context function that touches user-owned data takes a <code>%Scope{user: user}</code> as its first argument. This makes ownership filtering explicit and impossible to accidentally skip.</p>
<div class="code-block"><span class="cm"># accounts/scope.ex</span>
<span class="kw">defmodule</span> Speechwave.Accounts.Scope <span class="kw">do</span>
  <span class="kw">defstruct</span> [:user]
<span class="kw">end</span>

<span class="cm"># Usage in Talks context:</span>
<span class="kw">def</span> <span class="fn">list_talks</span>(%Scope{user: user}) <span class="kw">do</span>
  Repo.all(<span class="kw">from</span> t <span class="kw">in</span> Talk, <span class="kw">where:</span> t.user_id == ^user.id, ...)
<span class="kw">end</span></div>

<h3>API Key — Chrome Extension Auth</h3>
<p>The Chrome extension can't do magic links or OAuth — it's not a web page. Instead, every <code>User</code> gets a 32-byte hex API key (auto-generated on insert, visible in Settings). The extension sends this key when joining the Phoenix Channel. The server looks up the user by key and verifies they own the talk.</p>

<h3>Sudo Mode</h3>
<p><code>Accounts.sudo_mode?/2</code> returns <code>true</code> if the user authenticated within the last 20 minutes. Used to gate sensitive actions (e.g. changing email) without requiring a re-login on every visit. The <code>authenticated_at</code> field on the User struct is a virtual field set when the session token is verified.</p>
```

- [ ] **Step 4.2: Verify in browser**

Click "Authentication" in the sidebar. The stepper should show 4 steps. Click Next/Prev and verify the active node in the diagram changes. The two info cards for Magic Link / OAuth should sit side by side.

- [ ] **Step 4.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add Authentication chapter to explainer"
```

---

## Task 5: Emoji Journey Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-emoji-journey .content`

The core real-time flow — the most important chapter. Uses a 6-step stepper.

- [ ] **Step 5.1: Fill the Emoji Journey chapter**

Replace the comment inside `<div id="chapter-emoji-journey" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 4</div>
<h1 class="chapter-title">The Emoji Journey</h1>
<p class="chapter-lead">What happens from the moment an attendee taps a button to the moment a floating emoji appears on the speaker's slides. Six steps across the WebSocket, rate limiter, database, PubSub, and two different subscriber types.</p>

<div class="stepper">
  <div class="stepper-header">
    <span class="stepper-title">Tap → floating emoji — step by step</span>
    <div class="stepper-dots"></div>
  </div>
  <div class="stepper-body">
    <div class="stepper-step">
      <div class="step-title">Step 1 — Attendee taps a button</div>
      <div class="step-diagram">
        <div class="node active">📱 phx-click="react"</div>
        <div class="arrow">→</div>
        <div class="node">LiveView WebSocket</div>
        <div class="arrow">→</div>
        <div class="node">TalkLive.handle_event</div>
      </div>
      <div class="step-desc">The template uses <code>phx-click="react"</code> and <code>phx-value-emoji="🔥"</code>. Phoenix LiveView sends this over the existing WebSocket to <code>handle_event/3</code> on the server. No HTTP request is made — it's a push over the already-open connection.</div>
    </div>
    <div class="stepper-step">
      <div class="step-title">Step 2 — Rate limiter check</div>
      <div class="step-diagram">
        <div class="node dim">📱 Tap</div>
        <div class="arrow">→</div>
        <div class="node active">RateLimiter.allow?(socket.id)</div>
        <div class="arrow">→</div>
        <div class="node">ETS table lookup</div>
      </div>
      <div class="step-desc"><code>RateLimiter.allow?/1</code> checks an ETS table keyed by the LiveView socket ID (one bucket per browser tab). If less than 3 seconds have elapsed since the last allowed tap, it returns <code>false</code> and the event is silently dropped. If allowed, the current timestamp is written to ETS.</div>
    </div>
    <div class="stepper-step">
      <div class="step-title">Step 3 — Persist to database (if session active)</div>
      <div class="step-diagram">
        <div class="node dim">📱 Tap</div>
        <div class="arrow">→</div>
        <div class="node dim">Rate limit ✓</div>
        <div class="arrow">→</div>
        <div class="node active">Reactions.create_reaction/3</div>
        <div class="arrow">→</div>
        <div class="node">reactions table</div>
      </div>
      <div class="step-desc">If <code>Talks.get_active_session/1</code> returns a session, the reaction is inserted with <code>emoji</code>, the session ID, and <code>current_slide</code> (tracked in socket assigns, updated when <code>slide_changed</code> arrives). If no session is active, the reaction still broadcasts — it just isn't stored.</div>
    </div>
    <div class="stepper-step">
      <div class="step-title">Step 4 — Broadcast via PubSub</div>
      <div class="step-diagram">
        <div class="node dim">📱 Tap</div>
        <div class="arrow">→</div>
        <div class="node active">Endpoint.broadcast! "reactions:slug"</div>
        <div class="arrow">→</div>
        <div class="node">Phoenix.PubSub</div>
        <div class="arrow">→</div>
        <div class="node">all subscribers</div>
      </div>
      <div class="step-desc"><code>Endpoint.broadcast!/3</code> delivers to everyone subscribed to <code>"reactions:my-talk"</code> regardless of their type. Two things are subscribed: the LiveView process itself (subscribed on mount) and any ReactionChannel processes (subscribed on extension join). Neither knows the other exists.</div>
    </div>
    <div class="stepper-step">
      <div class="step-title">Step 5 — Back to the attendee's browser</div>
      <div class="step-diagram">
        <div class="node dim">PubSub</div>
        <div class="arrow">→</div>
        <div class="node active">TalkLive.handle_info</div>
        <div class="arrow">→</div>
        <div class="node">push_event "new_reaction"</div>
        <div class="arrow">→</div>
        <div class="node">EmojiStream JS hook</div>
      </div>
      <div class="step-desc"><code>handle_info/2</code> receives the broadcast and calls <code>push_event/3</code> to deliver a client-side event over the LiveView socket. The <code>EmojiStream</code> hook picks it up via <code>this.handleEvent("new_reaction", …)</code> and animates a floating emoji in the browser.</div>
    </div>
    <div class="stepper-step">
      <div class="step-title">Step 6 — To the speaker's Chrome extension</div>
      <div class="step-diagram">
        <div class="node dim">PubSub</div>
        <div class="arrow">→</div>
        <div class="node active">ReactionChannel</div>
        <div class="arrow">→</div>
        <div class="node">Channel WebSocket push</div>
        <div class="arrow">→</div>
        <div class="node">spawnEmoji()</div>
      </div>
      <div class="step-desc"><code>ReactionChannel</code> also receives the PubSub broadcast and pushes it directly to the extension's WebSocket. The content script receives it and calls <code>spawnEmoji()</code>, which creates a floating <code>&lt;span&gt;</code> over the slide presentation in the speaker's browser.</div>
    </div>
  </div>
  <div class="stepper-footer">
    <span class="step-counter"></span>
    <div class="step-btns">
      <button class="btn-step btn-prev">← Prev</button>
      <button class="btn-step btn-next">Next →</button>
    </div>
  </div>
</div>

<h3>Rate Limiting — Why ETS?</h3>
<div class="code-block"><span class="kw">def</span> <span class="fn">allow?</span>(session_id) <span class="kw">do</span>
  now = System.monotonic_time(<span class="at">:millisecond</span>)
  <span class="kw">case</span> :ets.lookup(<span class="at">@table</span>, session_id) <span class="kw">do</span>
    [{^session_id, last_at}] <span class="kw">when</span> now - last_at &lt; <span class="at">@cooldown_ms</span> -&gt; <span class="kw">false</span>
    _ -&gt; :ets.insert(<span class="at">@table</span>, {session_id, now}); <span class="kw">true</span>
  <span class="kw">end</span>
<span class="kw">end</span></div>
<div class="callout">
  <div class="callout-label">Why ETS and not the GenServer directly?</div>
  <p>The <code>RateLimiter</code> GenServer owns the ETS table but the table is <code>:public</code> with <code>read_concurrency: true</code>. Any process calls <code>allow?/1</code> directly against ETS — no message passing through the GenServer. With hundreds of attendees tapping simultaneously, routing everything through one GenServer mailbox would become a bottleneck. ETS reads are lock-free concurrent operations.</p>
</div>
```

- [ ] **Step 5.2: Verify in browser**

Click "Emoji Journey". The stepper should have 6 steps. Step through all 6. Verify that each step's active node is highlighted purple and prior nodes are dimmed. Try keyboard arrow keys.

- [ ] **Step 5.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add Emoji Journey chapter to explainer"
```

---

## Task 6: WebSockets Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-websockets .content`

Explains the two socket types in depth and why PubSub bridges them.

- [ ] **Step 6.1: Fill the WebSockets chapter**

Replace the comment inside `<div id="chapter-websockets" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 5</div>
<h1 class="chapter-title">WebSockets</h1>
<p class="chapter-lead">Two distinct WebSocket connections run simultaneously. They serve different clients, use different Phoenix abstractions, and connect through PubSub — without knowing about each other.</p>

<h3>The LiveView Socket — /live</h3>
<p>This powers the attendee's interactive page. Phoenix LiveView manages it completely automatically — no manual setup needed. When an attendee opens <code>/t/my-talk</code>, LiveView renders HTML server-side, then upgrades to a WebSocket for all subsequent interactions.</p>
<p>What it does:</p>
<ul>
  <li>Delivers <code>phx-click</code> events from the browser to <code>TalkLive.handle_event/3</code></li>
  <li>Receives <code>push_event</code> calls from the server to run client-side JS hooks</li>
  <li>Keeps the page in sync with diffs (partial re-renders)</li>
</ul>
<div class="code-block"><span class="cm"># endpoint.ex</span>
socket <span class="str">"/live"</span>, Phoenix.LiveView.Socket,
  <span class="at">websocket:</span> [<span class="at">connect_info:</span> [<span class="at">session:</span> <span class="at">@session_options</span>]]</div>

<h3>The Channel Socket — /socket</h3>
<p>A lower-level bare Phoenix Channel socket used by the Chrome extension. The extension isn't a web page, so it can't use LiveView. It only needs to <em>receive</em> messages and control sessions — Channels handle this perfectly.</p>
<p>Key differences from the LiveView socket:</p>
<ul>
  <li><strong>Authentication at join time</strong> — the extension passes <code>api_key</code> when joining the channel; the server verifies ownership against the talk</li>
  <li><strong><code>check_origin: false</code></strong> — allows connections from the <code>chrome-extension://</code> origin (which would otherwise be rejected)</li>
  <li><strong>Manual connect</strong> — the extension's content script creates a <code>Phoenix.Socket</code> object and calls <code>.connect()</code> and <code>.channel(topic).join()</code> explicitly</li>
</ul>
<div class="code-block"><span class="cm"># endpoint.ex</span>
socket <span class="str">"/socket"</span>, SpeechwaveWeb.UserSocket,
  <span class="at">websocket:</span> [<span class="at">check_origin:</span> <span class="kw">false</span>]

<span class="cm"># user_socket.ex</span>
channel <span class="str">"reactions:*"</span>, SpeechwaveWeb.ReactionChannel

<span class="kw">def</span> <span class="fn">connect</span>(_params, socket, _info), <span class="at">do:</span> {:ok, socket}
<span class="kw">def</span> <span class="fn">id</span>(_socket), <span class="at">do:</span> <span class="kw">nil</span></div>

<h3>Channel Join — API Key Auth</h3>
<p>When the extension joins, the server runs a <code>with</code> chain that must pass four checks. If any fails, the join is rejected with a reason the extension can surface to the speaker.</p>
<div class="code-block"><span class="kw">def</span> <span class="fn">join</span>(<span class="str">"reactions:"</span> &lt;&gt; slug, %{<span class="str">"api_key"</span> =&gt; api_key}, socket) <span class="kw">do</span>
  <span class="kw">with</span> {:talk,  %Talk{} = talk} &lt;- {:talk,  Talks.get_talk_by_slug(slug)},
       {:user,  %User{} = user} &lt;- {:user,  Accounts.get_user_by_api_key(api_key)},
       {:owner, <span class="kw">true</span>}          &lt;- {:owner, talk.user_id == user.id},
       {:capacity, :ok}         &lt;- {:capacity, Plans.check(:max_participants, user.plan,
                                     Presence.list(<span class="str">"reactions:#{slug}"</span>) |&gt; map_size())} <span class="kw">do</span>
    Phoenix.PubSub.subscribe(Speechwave.PubSub, <span class="str">"user:#{user.id}:disconnect"</span>)
    send(self(), :after_join)
    {:ok, assign(socket, <span class="at">talk:</span> talk, <span class="at">user:</span> user)}
  <span class="kw">else</span>
    {:talk,     <span class="kw">nil</span>}                      -&gt; {:error, %{<span class="at">reason:</span> <span class="str">"not_found"</span>}}
    {:user,     <span class="kw">nil</span>}                      -&gt; {:error, %{<span class="at">reason:</span> <span class="str">"unauthorized"</span>}}
    {:owner,    <span class="kw">false</span>}                    -&gt; {:error, %{<span class="at">reason:</span> <span class="str">"unauthorized"</span>}}
    {:capacity, {:error, :limit_reached}} -&gt; {:error, %{<span class="at">reason:</span> <span class="str">"capacity_reached"</span>}}
  <span class="kw">end</span>
<span class="kw">end</span></div>

<h3>Why PubSub Connects Them</h3>
<p><code>Endpoint.broadcast!/3</code> doesn't know or care whether subscribers are LiveView processes or Channel processes. It sends to everyone subscribed to the topic. This is what keeps the architecture clean — <code>handle_event</code> in <code>TalkLive</code> broadcasts the reaction without knowing anything about the extension or how many viewers are watching.</p>
<div class="callout">
  <div class="callout-label">Attendee count via Presence</div>
  <p>The <code>:after_join</code> message calls <code>Presence.track/3</code> to register the extension as a participant on the <code>"reactions:slug"</code> topic. <code>Presence.list/1</code> is then used at channel join time to count current participants and enforce plan capacity limits. See the Plans chapter for details.</p>
</div>
```

- [ ] **Step 6.2: Verify in browser**

Click "WebSockets". Verify the two code blocks render correctly. Check that the `with` chain code block is readable and the `else` branches align properly.

- [ ] **Step 6.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add WebSockets chapter to explainer"
```

---

## Task 7: Plans & Limits Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-plans .content`

New system. Covers the Plans module, two enforced features, and how enforcement happens at different points.

- [ ] **Step 7.1: Fill the Plans & Limits chapter**

Replace the comment inside `<div id="chapter-plans" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 6 — New</div>
<h1 class="chapter-title">Plans &amp; Limits</h1>
<p class="chapter-lead">Speechwave has three tiers — free, pro, and org. The <code>Plans</code> module is a pure function library that maps features to limits. Enforcement is scattered across the channel join and session start paths.</p>

<h3>The Plans Module</h3>
<div class="code-block"><span class="kw">defmodule</span> Speechwave.Plans <span class="kw">do</span>
  <span class="cm"># limit/2 — pure: what is the cap for this feature × plan?</span>
  <span class="kw">def</span> <span class="fn">limit</span>(<span class="at">:max_participants</span>,       <span class="at">:free</span>), <span class="at">do:</span> <span class="num">50</span>
  <span class="kw">def</span> <span class="fn">limit</span>(<span class="at">:full_sessions_per_month</span>, <span class="at">:free</span>), <span class="at">do:</span> <span class="num">10</span>
  <span class="kw">def</span> <span class="fn">limit</span>(<span class="at">:max_participants</span>,       <span class="at">:pro</span>),  <span class="at">do:</span> <span class="at">:unlimited</span>
  <span class="kw">def</span> <span class="fn">limit</span>(<span class="at">:full_sessions_per_month</span>, <span class="at">:pro</span>),  <span class="at">do:</span> <span class="at">:unlimited</span>
  <span class="kw">def</span> <span class="fn">limit</span>(feature, <span class="at">:org</span>), <span class="at">do:</span> limit(feature, <span class="at">:pro</span>)

  <span class="cm"># check/3 — :ok or {:error, :limit_reached}</span>
  <span class="kw">def</span> <span class="fn">check</span>(feature, plan, current_count) <span class="kw">do</span>
    <span class="kw">case</span> limit(feature, plan) <span class="kw">do</span>
      <span class="at">:unlimited</span>              -&gt; :ok
      max <span class="kw">when</span> current_count &lt; max -&gt; :ok
      _                       -&gt; {:error, <span class="at">:limit_reached</span>}
    <span class="kw">end</span>
  <span class="kw">end</span>
<span class="kw">end</span></div>

<h3>Two Enforced Limits</h3>
<table class="schema-table">
  <thead><tr><th>Feature</th><th>Free</th><th>Pro / Org</th><th>Enforced where</th></tr></thead>
  <tbody>
    <tr>
      <td><code>:max_participants</code></td>
      <td>50</td>
      <td>Unlimited</td>
      <td>Channel join — <code>Presence.list/1 |&gt; map_size()</code></td>
    </tr>
    <tr>
      <td><code>:full_sessions_per_month</code></td>
      <td>10</td>
      <td>Unlimited</td>
      <td>Channel <code>start_session</code> handler + DashboardLive mount</td>
    </tr>
  </tbody>
</table>

<h3>Participant Counting via Presence</h3>
<p><code>SpeechwaveWeb.Presence</code> tracks every connected Channel socket on the <code>"reactions:slug"</code> topic. At channel join, before accepting, the server counts current presences with <code>Presence.list("reactions:my-talk") |&gt; map_size()</code> and passes the result to <code>Plans.check/3</code>. If the free-tier limit of 50 is reached, the join is rejected with <code>"capacity_reached"</code>.</p>

<h3>Full Session Counting</h3>
<p>A "full session" is a completed <code>TalkSession</code> lasting more than 10 minutes (600 seconds). <code>Talks.count_full_sessions_this_month/1</code> queries across all of the user's talks for the current calendar month.</p>
<div class="code-block"><span class="cm"># Talks.count_full_sessions_this_month/1 (simplified)</span>
<span class="kw">from</span>(s <span class="kw">in</span> TalkSession,
  <span class="at">join:</span> t <span class="kw">in</span> Talk, <span class="at">on:</span> t.id == s.talk_id <span class="kw">and</span> t.user_id == ^user.id,
  <span class="at">where:</span> s.started_at &gt;= ^beginning_of_month,
  <span class="at">where:</span> not is_nil(s.ended_at),
  <span class="at">where:</span> fragment(<span class="str">"(strftime('%s', ?) - strftime('%s', ?)) > 600"</span>, s.ended_at, s.started_at)
)</div>
<div class="callout">
  <div class="callout-label">Where the check fires</div>
  <p>The session limit is checked in the <code>ReactionChannel</code> when the extension sends <code>"start_session"</code>. If the limit is reached, the channel replies with <code>{:error, %{reason: "session_limit_reached"}}</code> and no session is created. The dashboard also reads the count at mount to display usage to the speaker.</p>
</div>
```

- [ ] **Step 7.2: Verify in browser**

Click "Plans & Limits". The plans module code block should show the pattern-matched function clauses clearly. The enforcement table should have three columns with code values in the first column.

- [ ] **Step 7.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add Plans & Limits chapter to explainer"
```

---

## Task 8: Supervision Tree Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-supervision .content`

Updated tree with Presence and conditional DbBackup.

- [ ] **Step 8.1: Fill the Supervision Tree chapter**

Replace the comment inside `<div id="chapter-supervision" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 7</div>
<h1 class="chapter-title">Supervision Tree</h1>
<p class="chapter-lead">Every long-lived process in Elixir/OTP lives under a supervisor that restarts it if it crashes. Here's Speechwave's tree — and what happens when each child fails.</p>

<div class="code-block"><span class="cm"># application.ex</span>
children = [
  SpeechwaveWeb.Telemetry,       <span class="cm"># metrics</span>
  Speechwave.Repo,               <span class="cm"># Ecto / SQLite</span>
  {DNSCluster, <span class="at">query:</span> ...},     <span class="cm"># multi-node discovery</span>
  {Phoenix.PubSub, <span class="at">name:</span> Speechwave.PubSub},
  Speechwave.RateLimiter,        <span class="cm"># GenServer + ETS</span>
  SpeechwaveWeb.Endpoint,        <span class="cm"># HTTP + both WebSocket endpoints</span>
  SpeechwaveWeb.Presence,        <span class="cm"># participant tracking</span>
] ++ backup_children()           <span class="cm"># DbBackup if STORAGE_BUCKET is set</span>

<span class="kw">defp</span> <span class="fn">backup_children</span> <span class="kw">do</span>
  <span class="kw">if</span> System.get_env(<span class="str">"STORAGE_BUCKET"</span>), <span class="at">do:</span> [Speechwave.DbBackup], <span class="at">else:</span> []
<span class="kw">end</span></div>

<h3>What happens when each child crashes?</h3>
<table class="schema-table">
  <thead><tr><th>Process</th><th>On crash</th><th>Data loss?</th></tr></thead>
  <tbody>
    <tr>
      <td><code>RateLimiter</code></td>
      <td>Supervisor restarts it. New ETS table created empty.</td>
      <td>Yes — all cooldown state lost. Every user gets a fresh window. Acceptable for rate limiting.</td>
    </tr>
    <tr>
      <td><code>Presence</code></td>
      <td>Supervisor restarts it. Tracked presences cleared.</td>
      <td>Yes — participant count resets to 0 until extensions reconnect. Capacity checks temporarily permissive.</td>
    </tr>
    <tr>
      <td><code>DbBackup</code></td>
      <td>Supervisor restarts it. Timer resets (5-minute delay before next attempt).</td>
      <td>No database data lost — backup failure only means a snapshot wasn't uploaded.</td>
    </tr>
    <tr>
      <td><code>Repo</code></td>
      <td>Supervisor restarts it. All DB connections re-established.</td>
      <td>Any in-flight transaction is rolled back. Unlikely to crash in normal operation.</td>
    </tr>
  </tbody>
</table>

<div class="callout">
  <div class="callout-label">strategy: :one_for_one</div>
  <p>The supervisor uses <code>:one_for_one</code> — when a child crashes, only that child is restarted. The other children keep running. This is safe here because the processes don't share state with each other (beyond PubSub, which is itself supervised).</p>
</div>
```

- [ ] **Step 8.2: Verify in browser**

Click "Supervision Tree". The table should show four rows with monospace process names. The code block should render the conditional backup_children function clearly.

- [ ] **Step 8.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add Supervision Tree chapter to explainer"
```

---

## Task 9: DB Backup Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-db-backup .content`

New system. Covers the GenServer, VACUUM INTO, S3 upload, and conditional startup.

- [ ] **Step 9.1: Fill the DB Backup chapter**

Replace the comment inside `<div id="chapter-db-backup" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 8 — New</div>
<h1 class="chapter-title">DB Backup</h1>
<p class="chapter-lead"><code>Speechwave.DbBackup</code> is a GenServer that runs hourly SQLite backups and uploads them to S3-compatible object storage. It only starts when the <code>STORAGE_BUCKET</code> environment variable is set — so it never runs in development.</p>

<h3>How It Works</h3>
<div class="code-block"><span class="kw">use</span> GenServer

<span class="at">@initial_delay</span> :timer.minutes(<span class="num">5</span>)   <span class="cm"># wait for app to stabilize after boot</span>
<span class="at">@interval</span>      :timer.hours(<span class="num">1</span>)

<span class="kw">def</span> <span class="fn">init</span>(_opts) <span class="kw">do</span>
  Process.send_after(self(), <span class="at">:backup</span>, <span class="at">@initial_delay</span>)
  {:ok, %{}}
<span class="kw">end</span>

<span class="kw">def</span> <span class="fn">handle_info</span>(<span class="at">:backup</span>, state) <span class="kw">do</span>
  run_backup()
  Process.send_after(self(), <span class="at">:backup</span>, <span class="at">@interval</span>)
  {:noreply, state}
<span class="kw">end</span></div>

<h3>VACUUM INTO — Live Snapshot</h3>
<p>SQLite's <code>VACUUM INTO</code> creates a fully consistent, compacted copy of the database at a given path while the database remains live and writable. It's equivalent to an online backup — no locking, no downtime.</p>
<div class="code-block">SQL.query!(Repo, <span class="str">"VACUUM INTO '/tmp/speechwave_backup.db'"</span>, [])</div>
<div class="callout">
  <div class="callout-label">Why VACUUM INTO and not file copy?</div>
  <p>A plain file copy of a live SQLite database can capture it mid-transaction, producing a corrupt backup. <code>VACUUM INTO</code> is SQLite's purpose-built solution: it produces a clean, compacted snapshot that's guaranteed consistent. The file is also smaller because it compacts free pages.</p>
</div>

<h3>S3 Upload via Req</h3>
<p>After the snapshot is created, it's uploaded to S3-compatible object storage using <code>Req.put!/2</code> with the <code>aws_sigv4</code> option. The temporary file is deleted in the <code>after</code> block regardless of whether the upload succeeds.</p>
<div class="code-block">Req.put!(<span class="str">"#{endpoint}/#{bucket}/backup/speechwave.db"</span>,
  <span class="at">body:</span> File.read!(path),
  <span class="at">aws_sigv4:</span> [
    <span class="at">access_key_id:</span>     System.fetch_env!(<span class="str">"STORAGE_ACCESS_KEY_ID"</span>),
    <span class="at">secret_access_key:</span> System.fetch_env!(<span class="str">"STORAGE_SECRET_ACCESS_KEY"</span>),
    <span class="at">region:</span>            <span class="str">"auto"</span>,
    <span class="at">service:</span>           <span class="str">"s3"</span>
  ]
)</div>
<p>Required environment variables: <code>STORAGE_URL</code>, <code>STORAGE_BUCKET</code>, <code>STORAGE_ACCESS_KEY_ID</code>, <code>STORAGE_SECRET_ACCESS_KEY</code>. The presence of <code>STORAGE_BUCKET</code> is also the signal that tells the supervisor to start this process at all.</p>

<h3>Manual Trigger</h3>
<p>The GenServer is registered under its own module name, so you can trigger an immediate backup from IEx without waiting for the timer:</p>
<div class="code-block">Speechwave.DbBackup.run_now()</div>
```

- [ ] **Step 9.2: Verify in browser**

Click "DB Backup". Three code blocks should render. The callout explains VACUUM INTO. Verify no HTML escaping issues with the `>` in the callout.

- [ ] **Step 9.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add DB Backup chapter to explainer"
```

---

## Task 10: Chrome Extension Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-chrome-extension .content`

Covers popup, content script, channel auth, fireworks, slide tracking, and fullscreen re-parenting.

- [ ] **Step 10.1: Fill the Chrome Extension chapter**

Replace the comment inside `<div id="chapter-chrome-extension" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 9</div>
<h1 class="chapter-title">Chrome Extension</h1>
<p class="chapter-lead">The speaker-side client. Two parts: a popup UI for connection control, and a content script injected into Google Slides that connects to the Phoenix Channel and overlays emoji animations.</p>

<div class="two-col">
  <div class="info-card">
    <div class="info-card-label">Popup (popup.html + popup.js)</div>
    <p>The extension icon UI. Speaker enters their talk slug and clicks Connect. Sends a message to the content script via <code>chrome.runtime.sendMessage</code>. Also shows current slide number and a fireworks toggle.</p>
  </div>
  <div class="info-card">
    <div class="info-card-label">Content Script (content.js)</div>
    <p>Injected into Google Slides pages. Connects a Phoenix <code>Socket</code> to <code>/socket</code>, joins the <code>reactions:slug</code> Channel with the API key, listens for messages, and renders animations in an overlay div.</p>
  </div>
</div>

<h3>Channel Connection</h3>
<p>The content script connects using the phoenix.js client library, passing the API key as a join parameter:</p>
<div class="code-block"><span class="cm">// content.js (JavaScript)</span>
<span class="kw">const</span> socket = <span class="kw">new</span> <span class="fn">Phoenix.Socket</span>(<span class="str">"wss://speechwave.fly.dev/socket"</span>)
socket.<span class="fn">connect</span>()
<span class="kw">const</span> channel = socket.<span class="fn">channel</span>(<span class="str">`reactions/${slug}`</span>, { <span class="at">api_key:</span> apiKey })
channel.<span class="fn">join</span>()
  .<span class="fn">receive</span>(<span class="str">"ok"</span>, () =&gt; console.<span class="fn">log</span>(<span class="str">"connected"</span>))
  .<span class="fn">receive</span>(<span class="str">"error"</span>, ({ reason }) =&gt; console.<span class="fn">error</span>(reason))</div>

<h3>Fireworks Animation</h3>
<p>When the crowd converges on a single emoji, a radial burst fires instead of individual floaters. The trigger condition is intentionally compound:</p>
<div class="code-block"><span class="cm">// From lib/fireworks.js — pure function, tested with Jest</span>
<span class="kw">function</span> <span class="fn">checkFireworksTrigger</span>(inFlight, emoji, opts) {
  <span class="kw">const</span> count = inFlight[emoji] ?? <span class="num">0</span>
  <span class="kw">const</span> total = Object.<span class="fn">values</span>(inFlight).<span class="fn">reduce</span>((a, b) =&gt; a + b, <span class="num">0</span>)
  <span class="kw">return</span> count &gt;= opts.minCount &amp;&amp; (total &gt; <span class="num">0</span> &amp;&amp; count / total &gt;= opts.minPercent)
}</div>

<div class="collapsible">
  <div class="collapsible-trigger">
    <span class="collapsible-icon">▶</span>
    Why the compound trigger condition?
  </div>
  <div class="collapsible-body">
    <p>The absolute count guard (<code>MIN_COUNT = 5</code>) prevents bursts with tiny audiences — a single person tapping rapidly shouldn't trigger fireworks. The percentage guard (<code>MIN_PERCENT = 0.4</code>) prevents bursts when the crowd is diverse — the emoji must be <em>dominant</em>, not just frequent. A global cooldown (<code>8000ms</code>) prevents back-to-back bursts.</p>
  </div>
</div>

<h3>In-Flight Tracking</h3>
<p><code>spawnEmoji()</code> increments a per-emoji counter (<code>inFlight["❤️"]++</code>) when an element is created, and decrements it in the <code>animationend</code> listener. The 2.5s animation duration acts as a natural sliding window — <code>total_in_flight</code> reflects only the last ~2.5 seconds of reactions, making it a real-time proxy for current crowd engagement.</p>

<h3>Slide Tracking</h3>
<p>The extension detects slide changes using a <code>MutationObserver</code> watching for attribute changes on the Google Slides DOM. When the slide number changes, a <code>slide_changed</code> message is pushed to the Channel. The server broadcasts this to the <code>"slides:slug"</code> PubSub topic, which <code>TalkLive</code> is subscribed to — updating <code>current_slide</code> in assigns so the next reaction tap carries the right slide number.</p>

<div class="collapsible">
  <div class="collapsible-trigger">
    <span class="collapsible-icon">▶</span>
    The adapter registry
  </div>
  <div class="collapsible-body">
    <p>Different presentation tools expose the slide number differently. <code>adapters/index.js</code> picks the right adapter by URL pattern. The Google Slides adapter reads the slide number from a DOM input (<code>input[aria-label*="Slide"]</code>). This is brittle by nature — Google could change the DOM — but fixture-based Jest tests snapshot the selector so regressions are caught before they ship.</p>
  </div>
</div>

<h3>Fullscreen Re-parenting</h3>
<p>When Google Slides enters fullscreen mode, the browser creates a new stacking context for the fullscreen element. Any <code>position: fixed</code> overlays on <code>&lt;body&gt;</code> become invisible. The content script handles this by moving the overlay <code>&lt;div&gt;</code> into the fullscreen element when <code>fullscreenchange</code> fires:</p>
<div class="code-block">document.<span class="fn">addEventListener</span>(<span class="str">"fullscreenchange"</span>, () =&gt; {
  <span class="kw">const</span> overlay = document.<span class="fn">getElementById</span>(<span class="str">"speechwave-overlay"</span>)
  <span class="kw">if</span> (document.fullscreenElement) {
    document.fullscreenElement.<span class="fn">appendChild</span>(overlay) <span class="cm">// move into fullscreen</span>
  } <span class="kw">else</span> {
    document.body.<span class="fn">appendChild</span>(overlay)              <span class="cm">// move back</span>
  }
})</div>
```

- [ ] **Step 10.2: Verify in browser**

Click "Chrome Extension". Verify the two collapsible sections expand and collapse. The "Why the compound trigger condition?" section should show the MIN_COUNT / MIN_PERCENT explanation when expanded.

- [ ] **Step 10.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add Chrome Extension chapter to explainer"
```

---

## Task 11: Analytics Chapter

**Files:**
- Modify: `docs/explainer/index.html` — fill `#chapter-analytics .content`

Covers the aggregation query, bar chart rendering, and comparison mode.

- [ ] **Step 11.1: Fill the Analytics chapter**

Replace the comment inside `<div id="chapter-analytics" class="chapter"><div class="content">` with:

```html
<div class="chapter-eyebrow">Chapter 10</div>
<h1 class="chapter-title">Analytics</h1>
<p class="chapter-lead">After a talk, the speaker reviews per-slide engagement at <code>/sessions/:id</code>. A comparison mode at <code>/sessions/:id/compare/:other_id</code> renders two sessions side by side — useful for comparing a practice run to the real thing.</p>

<h3>The Aggregation Query</h3>
<p><code>Reactions.slide_reaction_totals/1</code> groups all reactions in a session by <code>(slide_number, emoji)</code> and returns a count per pair.</p>
<div class="code-block"><span class="kw">def</span> <span class="fn">slide_reaction_totals</span>(session_id) <span class="kw">do</span>
  <span class="kw">from</span>(r <span class="kw">in</span> Reaction,
    <span class="at">where:</span>    r.talk_session_id == ^session_id,
    <span class="at">group_by:</span> [r.slide_number, r.emoji],
    <span class="at">select:</span>   %{<span class="at">slide_number:</span> r.slide_number, <span class="at">emoji:</span> r.emoji, <span class="at">count:</span> count(r.id)},
    <span class="at">order_by:</span> [<span class="at">asc:</span> r.slide_number]
  ) |&gt; Repo.all()
<span class="kw">end</span></div>

<h3>Bar Charts Without a JS Library</h3>
<p><code>SessionAnalyticsLive</code> groups the query results by <code>slide_number</code> into a map, then renders a bar chart for each slide using Tailwind CSS. Heights are computed as percentages of the slide's maximum count — no JS charting library required.</p>

<div class="callout">
  <div class="callout-label">Slide 0 = "General"</div>
  <p>Reactions recorded before a session starts, or when no slide adapter could read the current slide, have <code>slide_number: 0</code>. The template renders these under a "General" label rather than "Slide 0".</p>
</div>

<h3>Comparison Mode</h3>
<p>At <code>/sessions/:id/compare/:other_id</code>, <code>SessionAnalyticsLive</code> loads both sessions and renders two charts side by side. The union of all slide numbers from both sessions is used — gaps are visible where one session had reactions on a slide the other didn't.</p>

<h3>Route Placement</h3>
<p>Analytics routes live inside the <code>:require_authenticated_user</code> live_session — a speaker must be logged in to view their session data.</p>
<div class="code-block">live <span class="str">"/sessions/:id"</span>,                     SessionAnalyticsLive, <span class="at">:show</span>
live <span class="str">"/sessions/:id/compare/:other_id"</span>,    SessionAnalyticsLive, <span class="at">:compare</span></div>
```

- [ ] **Step 11.2: Verify in browser**

Click "Analytics". Verify three sections render: the query code block, the callout, and the comparison description. Click through all 10 chapters to make sure navigation still works without any console errors.

- [ ] **Step 11.3: Commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: add Analytics chapter to explainer"
```

---

## Task 12: Polish, Final Check, and Cleanup

**Files:**
- Modify: `docs/explainer/index.html` — visual polish
- Delete: `docs/explainer.md` (optional — confirm with user first)

- [ ] **Step 12.1: Add responsive styles and final polish**

In the `<style>` block, append these rules before the closing `</style>`:

```css
/* ── Responsive ── */
@media (max-width: 700px) {
  .sidebar { width: 180px; }
  .content { padding: 24px 20px 60px; }
  .two-col { grid-template-columns: 1fr; }
  .step-diagram { flex-direction: column; align-items: flex-start; }
  .arch-diagram { flex-direction: column; }
  .arch-arrow { flex-direction: row; }
  .arch-arrow-line { transform: rotate(90deg); }
}
/* ── Smooth chapter transitions ── */
.chapter.active { animation: fadeIn 0.15s ease; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: none; } }
/* ── Stepper prev-button disabled state ── */
.btn-prev:disabled { opacity: 0.4; cursor: default; }
/* ── Selection ── */
::selection { background: #7c3aed33; }
```

- [ ] **Step 12.2: Full browser walkthrough**

Open `docs/explainer/index.html` fresh (no cache). Verify the complete checklist:

- [ ] All 10 sidebar items navigate to correct content
- [ ] All three steppers (Authentication, Emoji Journey) work with Next/Prev and keyboard arrows
- [ ] Both collapsibles in Chrome Extension chapter expand/collapse
- [ ] Schema tables render without overflow
- [ ] Code blocks don't have HTML entity escaping issues (check `>`, `<`, `&` characters)
- [ ] "new" badges appear on Authentication, Plans & Limits, DB Backup
- [ ] Responsive: at 600px wide, layout remains usable
- [ ] No console errors

- [ ] **Step 12.3: Commit final polish**

```bash
git add docs/explainer/index.html
git commit -m "docs: add polish and responsive styles to explainer"
```

- [ ] **Step 12.4: Run precommit**

```bash
mix precommit
```

Fix any issues reported. Re-commit if needed.

- [ ] **Step 12.5: Final commit**

```bash
git add docs/explainer/index.html
git commit -m "docs: complete interactive HTML explainer"
```
