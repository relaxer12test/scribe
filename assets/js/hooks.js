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
        this.chatState = { open: false, threadId: null }
        this.hasChatState = false

        const parseOpenParam = (value) => {
            if (!value) return null
            const normalized = value.toLowerCase()
            if (["open", "1", "true", "yes"].includes(normalized)) return true
            if (["closed", "0", "false", "no"].includes(normalized)) return false
            return null
        }

        const applyUrlState = () => {
            const params = new URLSearchParams(window.location.search)
            const chatParam = params.get("chat")
            const threadId = params.get("chat_thread")

            if (!chatParam && !threadId) return

            const openFromParam = parseOpenParam(chatParam)
            const open = openFromParam === null ? !!threadId : openFromParam

            this.pushEvent("sync_url_state", { open: open, thread_id: threadId })
        }

        const updateUrlFromState = () => {
            if (!window.history || !window.history.replaceState) return

            const url = new URL(window.location.href)

            if (this.chatState.open) {
                url.searchParams.set("chat", "open")
            } else {
                url.searchParams.set("chat", "closed")
            }

            if (this.chatState.threadId) {
                url.searchParams.set("chat_thread", this.chatState.threadId)
            } else {
                url.searchParams.delete("chat_thread")
            }

            const next = url.pathname + url.search + url.hash
            const current = window.location.pathname + window.location.search + window.location.hash

            if (next !== current) {
                window.history.replaceState(window.history.state, "", next)
            }
        }

        this.handleChatUrlState = ({ open, thread_id }) => {
            this.chatState = {
                open: !!open,
                threadId: thread_id ? String(thread_id) : null
            }
            this.hasChatState = true

            updateUrlFromState()
        }

        this.handlePageLoadStop = () => {
            if (this.hasChatState) {
                updateUrlFromState()
            }
        }

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

        this.handleEvent("chat_url_state", this.handleChatUrlState)

        document.addEventListener('keydown', this.handleKeydown)
        window.addEventListener('toggle-chat-bubble', this.handleToggle)
        window.addEventListener("phx:page-loading-stop", this.handlePageLoadStop)

        applyUrlState()
    },

    destroyed() {
        document.removeEventListener('keydown', this.handleKeydown)
        window.removeEventListener('toggle-chat-bubble', this.handleToggle)
        window.removeEventListener("phx:page-loading-stop", this.handlePageLoadStop)
    }
}

// Chat input hook for the bubble (contenteditable version)
Hooks.BubbleChatInput = {
    mounted() {
        this.selectedIndex = 0
        this.observer = null
        this.handleDropdownClick = null
        this.handleGlobalKeydown = null
        this.handleSelectionChange = null
        this.handleBlur = null
        this.lastCaretOffset = null
        this.focusRaf = null

        // Move cursor to end of contenteditable
        const moveCursorToEnd = () => {
            const range = document.createRange()
            range.selectNodeContents(this.el)
            range.collapse(false)
            const sel = window.getSelection()
            sel.removeAllRanges()
            sel.addRange(range)
        }

        const isSelectionInside = () => {
            const selection = window.getSelection()
            if (!selection || selection.rangeCount === 0) return false
            const range = selection.getRangeAt(0)
            return this.el.contains(range.startContainer) && this.el.contains(range.endContainer)
        }

        const getCaretOffset = () => {
            const selection = window.getSelection()
            if (!selection || selection.rangeCount === 0) return null
            const range = selection.getRangeAt(0)
            if (!this.el.contains(range.startContainer)) return null
            const preRange = range.cloneRange()
            preRange.selectNodeContents(this.el)
            preRange.setEnd(range.startContainer, range.startOffset)
            return preRange.toString().length
        }

        const setCaretOffset = (offset) => {
            const selection = window.getSelection()
            if (!selection) return
            let remaining = offset
            const walker = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT, null)
            let node = walker.nextNode()

            while (node) {
                const len = node.textContent.length
                if (remaining <= len) {
                    const range = document.createRange()
                    range.setStart(node, remaining)
                    range.collapse(true)
                    selection.removeAllRanges()
                    selection.addRange(range)
                    return
                }
                remaining -= len
                node = walker.nextNode()
            }

            moveCursorToEnd()
        }

        const cacheCaretOffset = () => {
            const offset = getCaretOffset()
            if (offset !== null) {
                this.lastCaretOffset = offset
            }
        }

        const restoreCaretOffset = () => {
            if (this.lastCaretOffset === null) {
                moveCursorToEnd()
                return
            }
            setCaretOffset(this.lastCaretOffset)
        }

        const getPlainText = () => this.el.textContent || ""

        const buildContentText = () => {
            let content = ""
            this.el.childNodes.forEach((node) => {
                if (node.nodeType === Node.TEXT_NODE) {
                    content += node.textContent
                    return
                }
                if (node.nodeType === Node.ELEMENT_NODE) {
                    const element = node
                    if (element.classList && element.classList.contains("inline-mention-pill")) {
                        const name = element.getAttribute("data-mention-name") || element.textContent || ""
                        content += `@${name}`
                        return
                    }
                    content += element.textContent || ""
                }
            })
            return content
        }

        const getMentionsFromDom = () => {
            const mentionNodes = this.el.querySelectorAll(".inline-mention-pill")
            return Array.from(mentionNodes).map((node) => ({
                contact_id: node.getAttribute("data-mention-id"),
                contact_name: node.getAttribute("data-mention-name"),
                crm_provider: node.getAttribute("data-mention-provider")
            }))
        }

        const syncMentions = () => {
            const mentions = getMentionsFromDom()
            this.el.setAttribute("data-mentions", JSON.stringify(mentions))
            return mentions
        }

        const createMentionPill = (contact) => {
            const displayName = contact.display_name || `${contact.firstname || ""} ${contact.lastname || ""}`.trim()
            const provider = contact.crm_provider || ""
            const initials = `${(contact.firstname || "").slice(0, 1)}${(contact.lastname || "").slice(0, 1)}`.toUpperCase()
            const providerLetter = provider === "hubspot" ? "H" : provider === "salesforce" ? "S" : ""

            const pill = document.createElement("span")
            pill.className = "inline-mention-pill"
            pill.setAttribute("contenteditable", "false")
            pill.setAttribute("data-mention-id", contact.id || "")
            pill.setAttribute("data-mention-name", displayName)
            pill.setAttribute("data-mention-provider", provider)

            const avatar = document.createElement("span")
            avatar.className = "inline-mention-pill-avatar"
            avatar.textContent = initials

            const badge = document.createElement("span")
            badge.className = `inline-mention-pill-badge ${provider === "hubspot" ? "bg-orange-500" : provider === "salesforce" ? "bg-blue-500" : ""}`.trim()
            badge.textContent = providerLetter
            avatar.appendChild(badge)

            const name = document.createElement("span")
            name.className = "inline-mention-pill-name"
            name.textContent = displayName

            pill.appendChild(avatar)
            pill.appendChild(name)

            return { pill, displayName }
        }

        const createRangeFromOffsets = (start, end) => {
            const range = document.createRange()
            let currentOffset = 0
            let startNode = null
            let startOffset = 0
            let endNode = null
            let endOffset = 0

            const walker = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT, null)
            let node = walker.nextNode()
            while (node) {
                const nextOffset = currentOffset + node.textContent.length
                if (startNode === null && start <= nextOffset) {
                    startNode = node
                    startOffset = Math.max(0, start - currentOffset)
                }
                if (endNode === null && end <= nextOffset) {
                    endNode = node
                    endOffset = Math.max(0, end - currentOffset)
                    break
                }
                currentOffset = nextOffset
                node = walker.nextNode()
            }

            if (!startNode || !endNode) {
                return null
            }

            range.setStart(startNode, startOffset)
            range.setEnd(endNode, endOffset)
            return range
        }

        const insertMention = (contact) => {
            const caretOffset = getCaretOffset()
            const text = getPlainText()
            const safeOffset = caretOffset === null ? text.length : caretOffset
            const before = text.slice(0, safeOffset)
            const match = before.match(/@(\w+)$/)
            if (!match) return false

            const start = safeOffset - match[0].length
            const end = safeOffset
            const range = createRangeFromOffsets(start, end)
            if (!range) return false

            const { pill } = createMentionPill(contact)
            const spaceNode = document.createTextNode(" ")
            const fragment = document.createDocumentFragment()
            fragment.appendChild(pill)
            fragment.appendChild(spaceNode)

            range.deleteContents()
            range.insertNode(fragment)

            const selection = window.getSelection()
            if (selection) {
                const newRange = document.createRange()
                newRange.setStart(spaceNode, spaceNode.textContent.length)
                newRange.collapse(true)
                selection.removeAllRanges()
                selection.addRange(newRange)
            }

            cacheCaretOffset()
            return true
        }

        this.handleEvent("focus_bubble_input", () => {
            this.el.focus()
            moveCursorToEnd()
            cacheCaretOffset()
        })

        this.handleEvent("update_bubble_input", ({ value }) => {
            if (value === "") {
                this.el.textContent = ""
            }
            this.el.focus()
            moveCursorToEnd()
            cacheCaretOffset()
        })

        const getDropdown = () => document.getElementById("bubble-mention-dropdown")
        const getLoadingIndicator = () => document.getElementById("bubble-mention-loading")

        const getDropdownItems = () => {
            const dropdown = getDropdown()
            if (!dropdown) return []
            return dropdown.querySelectorAll("[data-mention-item]")
        }

        const isDropdownOpen = () => {
            const dropdown = getDropdown()
            return dropdown !== null && getDropdownItems().length > 0
        }

        const isMentionUiActive = () => isDropdownOpen() || getLoadingIndicator() !== null

        const ensureFocus = () => {
            if (!this.el || !this.el.isConnected) return
            const wasActive = document.activeElement === this.el
            if (!wasActive) {
                this.el.focus({ preventScroll: true })
                restoreCaretOffset()
                return
            }
            if (!isSelectionInside()) {
                restoreCaretOffset()
            }
        }

        const updateSelection = (newIndex) => {
            const items = getDropdownItems()
            if (items.length === 0) return

            if (newIndex < 0) newIndex = items.length - 1
            if (newIndex >= items.length) newIndex = 0
            this.selectedIndex = newIndex

            items.forEach((item, idx) => {
                // Clear all selection classes
                item.classList.remove("bg-slate-100", "bg-slate-50", "bg-indigo-50")

                if (idx === this.selectedIndex) {
                    item.classList.add("bg-slate-100")
                    item.classList.remove("hover:bg-slate-50")
                    item.scrollIntoView({ block: "nearest" })
                } else {
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
                const inserted = insertMention(contact)
                if (inserted) {
                    const mentions = syncMentions()
                    const content = buildContentText()
                    this.pushEvent("input_change", { value: content })
                    this.pushEvent("select_mention", { mentions: JSON.stringify(mentions) })
                }
            } catch (error) {
                console.error("Failed to parse contact data", error)
            }
        }

        const closeDropdown = () => {
            ensureFocus()
            this.pushEvent("close_mention_dropdown", {})
        }

        // Reset index when dropdown content changes
        this.observer = new MutationObserver(() => {
            if (isMentionUiActive() && document.activeElement !== this.el) {
                ensureFocus()
            }
            const dropdown = getDropdown()
            if (dropdown) {
                const items = getDropdownItems()
                if (items.length > 0) {
                    this.selectedIndex = 0
                    updateSelection(0)
                }
            }
        })
        this.observer.observe(document.body, { childList: true, subtree: true })

        // Handle input for syncing with server
        this.el.addEventListener("input", () => {
            const text = buildContentText()
            cacheCaretOffset()
            this.pushEvent("input_change", { value: text })
        })

        this.handleSelectionChange = () => {
            if (!this.el || !this.el.isConnected) return
            if (!isSelectionInside()) return
            cacheCaretOffset()
        }
        document.addEventListener("selectionchange", this.handleSelectionChange)

        this.el.addEventListener("keydown", (e) => {
            const dropdownOpen = isDropdownOpen()

            if (dropdownOpen) {
                if (e.key === "ArrowUp") {
                    e.preventDefault()
                    e.stopPropagation()
                    updateSelection(this.selectedIndex - 1)
                    return false
                }
                if (e.key === "ArrowDown") {
                    e.preventDefault()
                    e.stopPropagation()
                    updateSelection(this.selectedIndex + 1)
                    return false
                }
                if (e.key === "Enter") {
                    e.preventDefault()
                    e.stopPropagation()
                    selectCurrent()
                    return false
                }
                if (e.key === "Tab" || e.key === "Escape") {
                    e.preventDefault()
                    e.stopPropagation()
                    closeDropdown()
                    return false
                }
            }

            // Enter to send (when dropdown closed)
            if (e.key === "Enter" && !e.shiftKey && !dropdownOpen) {
                e.preventDefault()
                const content = buildContentText()
                const mentions = syncMentions()
                if (content.trim() !== "" || mentions.length > 0) {
                    this.pushEvent("send_message", { content: content, mentions: JSON.stringify(mentions) })
                }
            }
        })

        this.handleBlur = () => {
            if (!isMentionUiActive()) return
            if (this.focusRaf) return
            this.focusRaf = requestAnimationFrame(() => {
                this.focusRaf = null
                ensureFocus()
            })
        }
        this.el.addEventListener("blur", this.handleBlur)

        this.handleGlobalKeydown = (e) => {
            if (!isDropdownOpen()) return
            if (!this.el || !this.el.isConnected) return

            if (document.activeElement !== this.el) {
                ensureFocus()
            }

            if (e.key === "ArrowUp") {
                e.preventDefault()
                e.stopPropagation()
                updateSelection(this.selectedIndex - 1)
                return
            }
            if (e.key === "ArrowDown") {
                e.preventDefault()
                e.stopPropagation()
                updateSelection(this.selectedIndex + 1)
                return
            }
            if (e.key === "Enter") {
                e.preventDefault()
                e.stopPropagation()
                selectCurrent()
                return
            }
            if (e.key === "Tab" || e.key === "Escape") {
                e.preventDefault()
                e.stopPropagation()
                closeDropdown()
            }
        }
        document.addEventListener("keydown", this.handleGlobalKeydown)

        // Handle clicks on dropdown items
        this.handleDropdownClick = (e) => {
            const item = e.target.closest("[data-mention-item]")
            const dropdown = getDropdown()
            if (item && dropdown && dropdown.contains(item)) {
                e.preventDefault()
                const contactData = item.getAttribute("data-contact")
                if (contactData) {
                    try {
                        const contact = JSON.parse(contactData)
                        const inserted = insertMention(contact)
                        if (inserted) {
                            const mentions = syncMentions()
                            const content = buildContentText()
                            this.pushEvent("input_change", { value: content })
                            this.pushEvent("select_mention", { mentions: JSON.stringify(mentions) })
                        }
                    } catch (error) {
                        console.error("Failed to parse contact data", error)
                    }
                }
            }
        }
        document.addEventListener("click", this.handleDropdownClick)
    },

    destroyed() {
        if (this.observer) {
            this.observer.disconnect()
        }
        if (this.focusRaf) {
            cancelAnimationFrame(this.focusRaf)
        }
        if (this.handleBlur) {
            this.el.removeEventListener("blur", this.handleBlur)
        }
        if (this.handleGlobalKeydown) {
            document.removeEventListener("keydown", this.handleGlobalKeydown)
        }
        if (this.handleDropdownClick) {
            document.removeEventListener("click", this.handleDropdownClick)
        }
        if (this.handleSelectionChange) {
            document.removeEventListener("selectionchange", this.handleSelectionChange)
        }
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
