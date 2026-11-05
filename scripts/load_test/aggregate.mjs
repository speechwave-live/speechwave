// Combines the JSON lines printed by each generator shard (stdin) into one result.
import { createInterface } from "node:readline";
const shards = [];
for await (const line of createInterface({ input: process.stdin })) {
  try { shards.push(JSON.parse(line)); } catch { /* ignore non-JSON lines */ }
}
const sum = (k) => shards.reduce((a, s) => a + s[k], 0);
const members = sum("members");
const taps = sum("taps_sent");
const probes = shards.flatMap((s) => s.latencies).sort((a, b) => a - b);
const channel = sum("channel_received") - probes.length;
const pct = (p) => (probes.length ? Math.round(probes[Math.min(probes.length - 1, Math.floor(probes.length * p))]) : null);
const seconds = Math.max(...shards.map((s) => s.seconds));
console.log(JSON.stringify({
  clients: members, join_failures: sum("join_failures"), taps_per_sec: +(taps / seconds).toFixed(1),
  taps_sent: taps,
  channel_delivery_pct: +(100 * channel / Math.max(1, taps)).toFixed(1),
  liveview_delivery_pct: +(100 * sum("liveview_pushes_received") / Math.max(1, (channel + probes.length) * members)).toFixed(1),
  probes: probes.length, latency_ms_p50: pct(0.5), latency_ms_p95: pct(0.95), latency_ms_max: pct(1),
}));
