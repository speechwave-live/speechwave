// Anonymous, stable identifier for an audience member, used only so the
// analytics page can count how many distinct people reacted.
//
// It is a random version-4 UUID: 122 bits drawn from the browser's
// cryptographically secure generator. Nothing about the person or device goes
// into it (no IP, user agent, fingerprint or account), so it cannot be derived
// from or traced back to anyone. It is kept in localStorage so that a page
// reload or a dropped conference Wi-Fi connection keeps the same identity.
//
// The storage key includes the talk slug, so the same browser gets a different,
// unlinkable ID for every talk.

const UUID_BYTES = 16
const UUID_FORMAT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function randomUuid() {
  // randomUUID() only exists in secure contexts (https or localhost).
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID()

  // Fallback: build a v4 UUID by hand from 16 random bytes.
  const b = crypto.getRandomValues(new Uint8Array(UUID_BYTES))
  b[6] = (b[6] & 0x0f) | 0x40 // version 4
  b[8] = (b[8] & 0x3f) | 0x80 // RFC 4122 variant
  const h = Array.from(b, x => x.toString(16).padStart(2, "0")).join("")
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

export function audienceId(talkSlug) {
  const key = `speechwave:audience:${talkSlug}`
  try {
    const existing = localStorage.getItem(key)
    if (existing && UUID_FORMAT.test(existing)) return existing
    const id = randomUuid()
    localStorage.setItem(key, id)
    return id
  } catch (_e) {
    // localStorage can throw (private mode, blocked site data). Fall back to
    // an ID that lasts for this page load only.
    return randomUuid()
  }
}
