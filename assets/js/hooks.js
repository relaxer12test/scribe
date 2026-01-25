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
        this.selectedIndex = 0

        this.handleEvent("focus_chat_input", () => {
            this.el.focus()
            this.el.setSelectionRange(this.el.value.length, this.el.value.length)
        })

        this.handleEvent("update_chat_input", ({ value }) => {
            this.el.value = value
            this.el.focus()
            this.el.setSelectionRange(value.length, value.length)
        })

        const getDropdown = () => document.getElementById("mention-dropdown")

        const getDropdownItems = () => {
            const dropdown = getDropdown()
            if (!dropdown) return []
            return dropdown.querySelectorAll("[data-mention-item]")
        }

        const isDropdownOpen = () => getDropdownItems().length > 0

        const hideDropdown = () => {
            const dropdown = getDropdown()
            if (dropdown) dropdown.style.display = "none"
        }

        const updateSelection = (newIndex) => {
            const items = getDropdownItems()
            if (items.length === 0) return

            if (newIndex < 0) newIndex = items.length - 1
            if (newIndex >= items.length) newIndex = 0
            this.selectedIndex = newIndex

            items.forEach((item, idx) => {
                if (idx === this.selectedIndex) {
                    item.classList.add("bg-indigo-50")
                    item.classList.remove("hover:bg-slate-50")
                    item.scrollIntoView({ block: "nearest" })
                } else {
                    item.classList.remove("bg-indigo-50")
                    item.classList.add("hover:bg-slate-50")
                }
            })
        }

        const selectCurrent = () => {
            const items = getDropdownItems()
            if (items.length === 0) return
            const item = items[this.selectedIndex]
            if (!item) return

            const contactData = item.getAttribute("data-contact")
            if (!contactData) return

            try {
                const contact = JSON.parse(contactData)
                const displayName = contact.display_name || ""

                // Update input value instantly - replace @query with @Name
                const currentValue = this.el.value
                const newValue = currentValue.replace(/@\w+$/, `@${displayName} `)
                this.el.value = newValue
                this.el.focus()
                this.el.setSelectionRange(newValue.length, newValue.length)

                // Hide dropdown instantly
                hideDropdown()

                // Sync with server in background
                this.pushEvent("select_mention", { contact: contactData })
            } catch (e) {
                console.error("Failed to parse contact data", e)
            }
        }

        const closeDropdown = () => {
            hideDropdown()
            this.el.focus()
            // Sync with server in background
            this.pushEvent("close_mention_dropdown", {})
        }

        // Reset index when dropdown content changes
        const observer = new MutationObserver(() => {
            const dropdown = getDropdown()
            if (dropdown && dropdown.style.display !== "none") {
                const items = getDropdownItems()
                if (items.length > 0) {
                    this.selectedIndex = 0
                    updateSelection(0)
                }
            }
        })
        observer.observe(document.body, { childList: true, subtree: true })

        this.el.addEventListener("keydown", (e) => {
            if (isDropdownOpen()) {
                if (e.key === "ArrowUp") {
                    e.preventDefault()
                    updateSelection(this.selectedIndex - 1)
                    return
                }
                if (e.key === "ArrowDown") {
                    e.preventDefault()
                    updateSelection(this.selectedIndex + 1)
                    return
                }
                if (e.key === "Enter") {
                    e.preventDefault()
                    selectCurrent()
                    return
                }
                if (e.key === "Tab" || e.key === "Escape") {
                    e.preventDefault()
                    closeDropdown()
                    return
                }
            }

            // Shift+Enter to send
            if (e.shiftKey && e.key === "Enter") {
                e.preventDefault()
                if (this.el.value.trim() !== "" && !this.el.disabled) {
                    this.pushEvent("send_message", {})
                }
            }
        })
    }
}

export default Hooks
