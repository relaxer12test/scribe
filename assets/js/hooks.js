let Hooks = {}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

Hooks.BrowserTimezone = {
    mounted() {
        let timezone = "Etc/UTC"
        try {
            const resolved = Intl.DateTimeFormat().resolvedOptions().timeZone
            if (resolved) {
                timezone = resolved
            }
        } catch (_) {
        }
        this.pushEvent("set_timezone", { timezone: timezone })
    }
}

Hooks.ChatInput = {
    mounted() {
        this.handleEvent("focus_chat_input", () => {
            this.el.focus()
            // Move cursor to end
            this.el.setSelectionRange(this.el.value.length, this.el.value.length)
        })
    }
}

export default Hooks
