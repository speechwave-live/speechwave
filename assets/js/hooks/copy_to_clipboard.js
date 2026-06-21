const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.clipboardText
      navigator.clipboard.writeText(text).then(() => {
        const idle = this.el.querySelector(".copy-icon-idle")
        const copied = this.el.querySelector(".copy-icon-copied")
        idle.classList.add("hidden")
        copied.classList.remove("hidden")
        clearTimeout(this.resetTimer)
        this.resetTimer = setTimeout(() => {
          idle.classList.remove("hidden")
          copied.classList.add("hidden")
        }, 1500)
        const msg = this.el.dataset.flashMessage
        if (msg) this.pushEvent("clipboard_copy", {message: msg})
      })
    })
  }
}

export default CopyToClipboard
