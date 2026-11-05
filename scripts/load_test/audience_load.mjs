// Load generator for the reaction pipeline. Throwaway tooling: run it ONLY
// against a local container (see README.md), never against production.
//
// Opens N simulated audience LiveView connections on /t/:slug, each reacting
// every --period ms (random phase), plus one extension-style listener on the
// reactions channel. Reports how many reactions were sent, how many reached
// the listener, tap-to-listener latency (via probe reactions), and how many
// push events the audience LiveViews received (the fan-out cost).
//
// Usage: node audience_load.mjs --slug S --api-key K --clients 200 \
//          [--period 3000] [--duration 60] [--base http://localhost:4000]
import { randomUUID } from "node:crypto";
import WebSocket from "ws";

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith("--")) acc.push([a.slice(2), all[i + 1]]);
    return acc;
  }, [])
);
const BASE = args.base ?? "http://localhost:4000";
const WS_BASE = BASE.replace(/^http/, "ws");
const SLUG = args.slug;
const API_KEY = args["api-key"];
const N = Number(args.clients ?? 50);
// --listener false: a load-only shard (no channel listener, no probe). Several
// shards run in parallel so one Node process is not the bottleneck.
const LISTENER = args.listener !== "false";
// 3200 ms: just over the server cooldown, so taps are not dropped by timer jitter
const PERIOD = Number(args.period ?? 3200);
const DURATION = Number(args.duration ?? 60) * 1000;
const PROBE_EVERY = 5000;
const EMOJIS = ["❤️", "😂", "👏", "🤯", "🎉", "😮", "🎯", "🔥", "💡"];
if (!SLUG || !API_KEY) throw new Error("--slug and --api-key are required");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const stats = { sent: 0, pushesReceived: 0, joinFailures: 0, channelReceived: 0 };
const probeSentAt = new Map(); // probe emoji -> performance.now() at send
const latencies = [];

function openWs(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url, { headers });
    ws.on("open", () => resolve(ws));
    ws.on("error", () => reject(new Error(`ws error ${url}`)));
  });
}

// One audience member: fetch the page, join the LiveView, send audience_id.
async function audienceMember(index) {
  const res = await fetch(`${BASE}/t/${SLUG}`);
  const cookie = res.headers.getSetCookie().map((c) => c.split(";")[0]).join("; ");
  const html = await res.text();
  const csrf = /<meta name="csrf-token" content="([^"]+)"/.exec(html)?.[1];
  const main = /<div[^>]*data-phx-main[^>]*>/.exec(html)?.[0];
  const id = /id="(phx-[^"]+)"/.exec(main ?? "")?.[1];
  const session = /data-phx-session="([^"]+)"/.exec(main ?? "")?.[1];
  const stat = /data-phx-static="([^"]+)"/.exec(main ?? "")?.[1];
  if (!csrf || !id || !session) throw new Error("could not parse LiveView markup");

  const ws = await openWs(`${WS_BASE}/live/websocket?_csrf_token=${encodeURIComponent(csrf)}&vsn=2.0.0`, { Cookie: cookie });
  const topic = `lv:${id}`;
  let ref = 1;
  const joinRef = "1";
  const send = (event, payload, t = topic) =>
    ws.send(JSON.stringify([joinRef, String(++ref), t, event, payload]));

  // After the join reply, pushes are only counted with a substring test: parsing
  // every push as JSON made the generator itself the bottleneck at high N.
  let isJoined = false;
  const joined = new Promise((resolve, reject) => {
    ws.on("message", (data) => {
      const text = data.toString();
      if (isJoined) {
        if (text.includes('"new_reaction"')) stats.pushesReceived++;
        return;
      }
      const [, , t, event, payload] = JSON.parse(text);
      if (t === topic && event === "phx_reply") {
        if (payload.status === "ok") { isJoined = true; resolve(); }
        else reject(new Error("join " + JSON.stringify(payload).slice(0, 300)));
      }
    });
  });
  ws.send(
    JSON.stringify([
      joinRef, "1", topic, "phx_join",
      { url: `${BASE}/t/${SLUG}`, params: { _csrf_token: csrf, _mounts: 0 }, session, static: stat },
    ])
  );
  await joined;
  send("event", { type: "hook", event: "audience_id", value: { id: randomUUID() } });
  const heartbeat = setInterval(() => ws.send(JSON.stringify([null, String(++ref), "phoenix", "heartbeat", {}])), 30000);

  const react = (emoji) => {
    send("event", { type: "click", event: "react", value: { emoji } });
    stats.sent++;
  };
  return { ws, react, stop: () => { clearInterval(heartbeat); ws.close(); } };
}

// Extension-style listener on the reactions channel.
async function listener() {
  const ws = await openWs(`${WS_BASE}/socket/websocket?vsn=2.0.0`);
  const topic = `reactions:${SLUG}`;
  const ready = new Promise((resolve, reject) => {
    ws.on("message", (data) => {
      const [, , t, event, payload] = JSON.parse(data.toString());
      if (t === topic && event === "phx_reply") {
        payload.status === "ok" ? resolve() : reject(new Error("channel join " + JSON.stringify(payload)));
      } else if (t === topic && event === "new_reaction") {
        stats.channelReceived++;
        const sentAt = probeSentAt.get(payload.emoji);
        if (sentAt !== undefined) {
          latencies.push(performance.now() - sentAt);
          probeSentAt.delete(payload.emoji);
        }
      }
    });
  });
  ws.send(JSON.stringify(["1", "1", topic, "phx_join", { api_key: API_KEY }]));
  await ready;
  setInterval(() => ws.send(JSON.stringify([null, "hb", "phoenix", "heartbeat", {}])), 30000);
  return ws;
}

const pct = (arr, p) => (arr.length ? arr.slice().sort((a, b) => a - b)[Math.min(arr.length - 1, Math.floor(arr.length * p))] : NaN);

if (LISTENER) await listener();
console.log(`listener joined; connecting ${N} audience members...`);

const members = [];
for (let i = 0; i < N; i += 25) {
  const batch = await Promise.allSettled(
    Array.from({ length: Math.min(25, N - i) }, (_, j) => audienceMember(i + j))
  );
  for (const r of batch) r.status === "fulfilled" ? members.push(r.value) : (stats.joinFailures++, console.error(r.reason.message));
}
console.log(`${members.length}/${N} connected (${stats.joinFailures} failed); reacting for ${DURATION / 1000}s`);

const timers = [];
members.forEach((m, i) => {
  // random phase so the load is spread out rather than arriving in lockstep
  timers.push(setTimeout(() => {
    m.react(EMOJIS[i % EMOJIS.length]);
    timers.push(setInterval(() => m.react(EMOJIS[Math.floor(Math.random() * EMOJIS.length)]), PERIOD));
  }, Math.random() * PERIOD));
});
// Probe: a dedicated extra member (not part of the load) sends a uniquely
// named "emoji" the listener can time, so its taps are never rate limited.
const probe = LISTENER ? await audienceMember(-1) : null;
let probeSeq = 0;
if (probe) timers.push(setInterval(() => {
  const tag = `probe${probeSeq++}`;
  probeSentAt.set(tag, performance.now());
  probe.react(tag);
  stats.sent--; // probes are not part of the load count
}, PROBE_EVERY));

const t0 = performance.now();
await sleep(DURATION);
timers.forEach((t) => { clearTimeout(t); clearInterval(t); });
await sleep(3000); // let in-flight broadcasts land
const secs = (performance.now() - t0 - 3000) / 1000;

// Raw counts for one shard; aggregate.mjs combines the shards.
console.log(JSON.stringify({
  members: members.length + (probe ? 1 : 0),
  join_failures: stats.joinFailures,
  seconds: Math.round(secs),
  taps_sent: stats.sent,
  channel_received: stats.channelReceived,
  probes: latencies.length,
  liveview_pushes_received: stats.pushesReceived,
  latencies,
}));
members.forEach((m) => m.stop());
probe?.stop();
process.exit(0);
