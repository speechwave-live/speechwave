import {audienceId} from "../audience_id"

// Tell the server who this is. On a free-plan talk this is also what claims
// the visitor's place, so the server sends no reactions until it arrives.
//
// The id is looked up once and kept on the hook. When localStorage is
// blocked, audienceId() makes up a new random id on every call, so asking
// again on a reconnect would claim a second place while the first is still
// held for its grace period. On a full talk that person would be turned away.
function sendAudienceId(hook) {
  hook.audienceId ??= audienceId(hook.el.dataset.talkSlug)
  hook.pushEvent("audience_id", {id: hook.audienceId})
}

const EmojiButtons = {
  // A reconnect (network blip, server restart) starts a fresh LiveView
  // process, but LiveView keeps the existing hook and calls reconnected()
  // instead of mounted(). Send the id again so the new process recognises
  // the same person and picks up their place.
  reconnected() {
    sendAudienceId(this)
  },

  mounted() {
    sendAudienceId(this)

    this.el.addEventListener("click", (e) => {
      if (e.target.tagName !== "BUTTON") return;
      if (e.target.disabled) return;

      const buttons = this.el.querySelectorAll("button");
      const label = this.el.querySelector(".cooldown-label");

      // Delay disabling until the next tick so phx-click propagates to Phoenix first.
      // Phoenix's delegated listener fires at the document level (after bubble), and
      // skips clicks on disabled buttons — so we must not disable synchronously here.
      setTimeout(() => {
        buttons.forEach(b => b.setAttribute("disabled", "true"));
        this.el.classList.add("cooling-down");

        let remaining = 3;
        if (label) label.textContent = `Cooling down… ${remaining}s`;

        const tick = setInterval(() => {
          remaining -= 1;
          if (label) {
            label.textContent = remaining > 0 ? `Cooling down… ${remaining}s` : "Tap to react";
          }
          if (remaining <= 0) {
            clearInterval(tick);
            buttons.forEach(b => b.removeAttribute("disabled"));
            this.el.classList.remove("cooling-down");
          }
        }, 1000);
      }, 0);
    });
  }
};

export default EmojiButtons;
