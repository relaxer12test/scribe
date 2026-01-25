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

// Global keyboard shortcut handler (⌘K to open chat bubble)
Hooks.GlobalKeyboard = {
    mounted() {
        this.handleKeydown = (e) => {
            // ⌘K (Mac) or Ctrl+K (Windows/Linux) to toggle chat bubble
            if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
                e.preventDefault()
                // Find the chat bubble container and dispatch a custom event
                // The ChatBubble hook will listen for this event
                window.dispatchEvent(new CustomEvent('toggle-chat-bubble'))
            }
        }

        document.addEventListener('keydown', this.handleKeydown)
    },

    destroyed() {
        document.removeEventListener('keydown', this.handleKeydown)
    }
}

// Chat Bubble container hook
Hooks.ChatBubble = {
    mounted() {
        // Handle Escape key to close bubble
        this.handleKeydown = (e) => {
            if (e.key === 'Escape') {
                const panel = document.getElementById('chat-panel')
                if (panel) {
                    this.pushEvent('close_bubble', {})
                }
            }
        }

        // Listen for global toggle event (from ⌘K shortcut)
        this.handleToggle = () => {
            this.pushEvent('toggle_bubble', {})
        }

        document.addEventListener('keydown', this.handleKeydown)
        window.addEventListener('toggle-chat-bubble', this.handleToggle)
    },

    destroyed() {
        document.removeEventListener('keydown', this.handleKeydown)
        window.removeEventListener('toggle-chat-bubble', this.handleToggle)
    }
}

// Chat input hook for the bubble
Hooks.BubbleChatInput = {
    mounted() {
        this.selectedIndex = 0

        this.handleEvent("focus_bubble_input", () => {
            this.el.focus()
            this.el.setSelectionRange(this.el.value.length, this.el.value.length)
        })

        this.handleEvent("update_bubble_input", ({ value }) => {
            this.el.value = value
            this.el.focus()
            this.el.setSelectionRange(value.length, value.length)
        })

        const getDropdown = () => document.getElementById("bubble-mention-dropdown")

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

                // Update input value - remove @query
                const currentValue = this.el.value
                const newValue = currentValue.replace(/@\w+$/, '')
                this.el.value = newValue
                this.el.focus()
                this.el.setSelectionRange(newValue.length, newValue.length)

                // Hide dropdown instantly
                hideDropdown()

                // Sync with server
                this.pushEvent("select_mention", { contact: contactData })
            } catch (e) {
                console.error("Failed to parse contact data", e)
            }
        }

        const closeDropdown = () => {
            hideDropdown()
            this.el.focus()
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
