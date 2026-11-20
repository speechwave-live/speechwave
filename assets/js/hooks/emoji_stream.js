// Reactions arrive in batches (about four a second), each one a list of
// emoji. The batch is spread across the tick that follows, so a busy room
// looks like a stream and not a burst.
const BATCH_SPREAD_MS = 250;

function floatEmoji(container, emoji) {
  const el = document.createElement("span");
  el.textContent = emoji;
  el.className = "floating-emoji";
  el.style.left = Math.floor(Math.random() * 80) + "%";
  el.style.animationDelay = Math.floor(Math.random() * BATCH_SPREAD_MS) + "ms";
  container.appendChild(el);
  el.addEventListener("animationend", () => el.remove());
}

const EmojiStream = {
  mounted() {
    this.handleEvent("reactions_batch", ({ emojis }) => {
      emojis.forEach((emoji) => floatEmoji(this.el, emoji));
    });
  }
};

export default EmojiStream;
