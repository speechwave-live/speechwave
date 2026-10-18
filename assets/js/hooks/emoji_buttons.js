import {audienceId} from "../audience_id"

const EmojiButtons = {
  mounted() {
    // Tell the server who this is. Runs again after a reconnect, which starts
    // a fresh LiveView process, so the same person is recognised.
    this.pushEvent("audience_id", {id: audienceId(this.el.dataset.talkSlug)})

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
