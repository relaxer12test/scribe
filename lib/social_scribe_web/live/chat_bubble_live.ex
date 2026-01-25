defmodule SocialScribeWeb.ChatBubbleLive do
  @moduledoc """
  A floating chat bubble component that can be accessed from any dashboard page.
  Supports global ⌘K shortcut, streaming responses, and rich mention chips.
  """
  use SocialScribeWeb, :live_view

  alias SocialScribe.Chat
  alias SocialScribe.ChatAssistant
  alias SocialScribe.Accounts

  require Logger

  @impl true
  def mount(_params, session, socket) do
    user = get_user_from_session(session)

    if user do
      hubspot_credential = Accounts.get_user_hubspot_credential(user.id)
      salesforce_credential = Accounts.get_user_credential(user, "salesforce")

      socket =
        socket
        |> assign(:current_user, user)
        |> assign(:threads, Chat.list_user_threads(user.id))
        |> assign(:current_thread, nil)
        |> assign(:messages, %{})
        |> assign(:active_tab, :chat)
        |> assign(:bubble_open, false)
        |> assign(:input_value, "")
        |> assign(:mentions, [])
        |> assign(:mention_chips, [])
        |> assign(:mention_search_results, [])
        |> assign(:mention_query, nil)
        |> assign(:sending, false)
        |> assign(:pending_message, nil)
        |> assign(:streaming, false)
        |> assign(:streaming_content, "")
        |> assign(:hubspot_credential, hubspot_credential)
        |> assign(:salesforce_credential, salesforce_credential)

      {:ok, socket, layout: false}
    else
      {:ok, assign(socket, :current_user, nil), layout: false}
    end
  end

  defp get_user_from_session(session) do
    case session["user_token"] do
      nil -> nil
      token -> Accounts.get_user_by_session_token(token)
    end
  end

  @impl true
  def render(assigns) do
    if assigns.current_user do
      render_chat_bubble(assigns)
    else
      ~H"""
      <div></div>
      """
    end
  end

  defp render_chat_bubble(assigns) do
    ~H"""
    <div id="chat-bubble-container" phx-hook="ChatBubble">
      <!-- Floating Action Button (FAB) - visible when sidebar is closed -->
      <button
        :if={!@bubble_open}
        phx-click="toggle_bubble"
        class="fixed bottom-6 right-6 z-50 w-14 h-14 rounded-full bg-indigo-600 text-white shadow-lg hover:bg-indigo-700 hover:shadow-xl transition-all duration-200 flex items-center justify-center group"
        title="Ask Anything (⌘K)"
      >
        <.icon name="hero-chat-bubble-left-right" class="h-6 w-6" />
        <span class="absolute -top-8 right-0 px-2 py-1 bg-slate-800 text-white text-xs rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap">
          ⌘K
        </span>
      </button>

      <!-- Overlay backdrop - click to close -->
      <div
        :if={@bubble_open}
        id="chat-overlay"
        class="fixed inset-0 bg-black/20 z-40 chat-overlay-enter"
        phx-click="close_bubble"
      >
      </div>

      <!-- Right Sidebar Panel -->
      <div
        :if={@bubble_open}
        id="chat-panel"
        class="fixed top-0 right-0 h-full w-[28rem] bg-white shadow-2xl z-50 flex flex-col chat-sidebar-enter"
      >
        <!-- Header -->
        <div class="bg-gradient-to-r from-indigo-600 to-indigo-700 px-5 py-4 flex items-center justify-between flex-shrink-0">
          <h2 class="text-white font-semibold text-lg flex items-center gap-2">
            <.icon name="hero-sparkles" class="h-5 w-5" />
            Ask Anything
          </h2>
          <div class="flex items-center gap-1">
            <button
              phx-click="new_chat"
              class="p-2 text-white/70 hover:text-white hover:bg-white/10 rounded-lg transition-colors"
              title="New conversation"
            >
              <.icon name="hero-plus" class="h-5 w-5" />
            </button>
            <button
              phx-click="close_bubble"
              class="p-2 text-white/70 hover:text-white hover:bg-white/10 rounded-lg transition-colors"
              title="Close (Esc)"
            >
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </button>
          </div>
        </div>

        <!-- Tabs -->
        <div class="border-b border-slate-200 px-5 flex bg-slate-50 flex-shrink-0">
          <button
            phx-click="switch_tab"
            phx-value-tab="chat"
            class={[
              "px-4 py-3 text-sm font-medium border-b-2 -mb-px transition-colors",
              @active_tab == :chat && "border-indigo-600 text-indigo-600",
              @active_tab != :chat && "border-transparent text-slate-500 hover:text-slate-700"
            ]}
          >
            Chat
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="history"
            class={[
              "px-4 py-3 text-sm font-medium border-b-2 -mb-px transition-colors",
              @active_tab == :history && "border-indigo-600 text-indigo-600",
              @active_tab != :history && "border-transparent text-slate-500 hover:text-slate-700"
            ]}
          >
            History
          </button>
        </div>

        <!-- Content Area - scrollable -->
        <div class="flex-1 overflow-y-auto min-h-0">
          <%= if @active_tab == :chat do %>
            <div class="p-5 space-y-4" id="chat-messages">
              <!-- Welcome message -->
              <%= if is_nil(@current_thread) || map_size(@messages) == 0 do %>
                <div class="flex gap-3">
                  <div class="flex-shrink-0 w-9 h-9 rounded-full bg-indigo-100 flex items-center justify-center">
                    <.icon name="hero-sparkles" class="h-5 w-5 text-indigo-600" />
                  </div>
                  <div class="bg-slate-100 rounded-2xl px-4 py-3 max-w-sm">
                    <p class="text-sm text-slate-700">
                      Ask me anything about your meetings and CRM contacts! Use <span class="font-medium">@</span> to mention a contact for context.
                    </p>
                  </div>
                </div>
              <% else %>
                <!-- Messages grouped by date -->
                <%= for {date, msgs} <- @messages do %>
                  <div class="flex items-center gap-4 py-2">
                    <div class="flex-1 border-t border-slate-200"></div>
                    <span class="text-xs text-slate-400 font-medium">{format_date(date)}</span>
                    <div class="flex-1 border-t border-slate-200"></div>
                  </div>

                  <%= for msg <- msgs do %>
                    <div class={["flex gap-3", msg.role == "user" && "flex-row-reverse"]}>
                      <div class="flex-shrink-0">
                        <%= if msg.role == "user" do %>
                          <div class="w-9 h-9 rounded-full bg-indigo-600 flex items-center justify-center text-white text-sm font-medium">
                            {String.first(@current_user.email) |> String.upcase()}
                          </div>
                        <% else %>
                          <div class="w-9 h-9 rounded-full bg-indigo-100 flex items-center justify-center">
                            <.icon name="hero-sparkles" class="h-5 w-5 text-indigo-600" />
                          </div>
                        <% end %>
                      </div>

                      <div class={[
                        "rounded-2xl px-4 py-3 max-w-sm",
                        msg.role == "user" && "bg-indigo-600 text-white",
                        msg.role == "assistant" && "bg-slate-100 text-slate-700"
                      ]}>
                        <p class="text-sm whitespace-pre-wrap">{render_content_with_chips(msg.content, msg.mentions)}</p>

                        <!-- Sources -->
                        <%= if msg.role == "assistant" && has_sources?(msg) do %>
                          <div class="mt-3 pt-3 border-t border-slate-200/50">
                            <p class="text-xs font-medium text-slate-500 mb-2">Sources</p>
                            <div class="space-y-1">
                              <%= for source <- msg.sources["meetings"] || [] do %>
                                <.link
                                  href={~p"/dashboard/meetings/#{source["meeting_id"]}"}
                                  class="flex items-center gap-2 text-xs text-indigo-600 hover:underline"
                                >
                                  <.icon name="hero-document-text" class="h-3.5 w-3.5" />
                                  <span class="truncate">{source["title"]}</span>
                                </.link>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              <% end %>

              <!-- Pending message -->
              <div :if={@sending && @pending_message} class="flex gap-3 flex-row-reverse">
                <div class="flex-shrink-0">
                  <div class="w-9 h-9 rounded-full bg-indigo-600 flex items-center justify-center text-white text-sm font-medium">
                    {String.first(@current_user.email) |> String.upcase()}
                  </div>
                </div>
                <div class="rounded-2xl px-4 py-3 max-w-sm bg-indigo-600 text-white">
                  <p class="text-sm whitespace-pre-wrap">{@pending_message}</p>
                </div>
              </div>

              <!-- Streaming response -->
              <div :if={@streaming} class="flex gap-3">
                <div class="flex-shrink-0">
                  <div class="w-9 h-9 rounded-full bg-indigo-100 flex items-center justify-center">
                    <.icon name="hero-sparkles" class="h-5 w-5 text-indigo-600" />
                  </div>
                </div>
                <div class="rounded-2xl px-4 py-3 max-w-sm bg-slate-100 text-slate-700">
                  <p class="text-sm whitespace-pre-wrap">
                    {@streaming_content}<span class="streaming-cursor">▌</span>
                  </p>
                </div>
              </div>

              <!-- Thinking indicator (non-streaming) -->
              <div :if={@sending && !@streaming} class="flex gap-3">
                <div class="flex-shrink-0">
                  <div class="w-9 h-9 rounded-full bg-indigo-100 flex items-center justify-center">
                    <.icon name="hero-arrow-path" class="h-5 w-5 text-indigo-600 animate-spin" />
                  </div>
                </div>
                <div class="rounded-2xl px-4 py-3 bg-slate-100">
                  <p class="text-sm text-slate-500">Thinking...</p>
                </div>
              </div>
            </div>
          <% else %>
            <!-- History tab -->
            <div class="divide-y divide-slate-100">
              <%= if Enum.empty?(@threads) do %>
                <div class="p-8 text-center text-slate-500">
                  <.icon name="hero-chat-bubble-left-right" class="h-12 w-12 mx-auto mb-3 text-slate-300" />
                  <p class="text-sm font-medium">No conversations yet</p>
                  <p class="text-xs mt-1">Start a new chat to begin</p>
                </div>
              <% else %>
                <%= for thread <- @threads do %>
                  <button
                    type="button"
                    phx-click="select_thread"
                    phx-value-id={thread.id}
                    class={[
                      "w-full px-5 py-4 text-left hover:bg-slate-50 transition-colors",
                      @current_thread && @current_thread.id == thread.id && "bg-indigo-50"
                    ]}
                  >
                    <div class="flex items-center justify-between">
                      <span class="text-sm font-medium text-slate-900 truncate">
                        {thread.title || "New conversation"}
                      </span>
                      <span class="text-xs text-slate-500 ml-2 flex-shrink-0">
                        {format_thread_time(thread)}
                      </span>
                    </div>
                    <p :if={first_message(thread)} class="text-xs text-slate-500 truncate mt-1">
                      {first_message(thread).content}
                    </p>
                  </button>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Input Area -->
        <div class="border-t border-slate-200 p-4 bg-white flex-shrink-0">
          <div class="relative">
            <!-- Mention autocomplete dropdown -->
            <div
              :if={@mention_query && length(@mention_search_results) > 0}
              id="bubble-mention-dropdown"
              class="absolute bottom-full left-0 mb-2 w-full bg-white rounded-xl shadow-lg border border-slate-200 max-h-48 overflow-y-auto z-10"
            >
              <%= for {contact, idx} <- Enum.with_index(@mention_search_results) do %>
                <button
                  type="button"
                  data-mention-item
                  data-contact={contact_json(contact)}
                  phx-click="select_mention"
                  phx-value-contact={contact_json(contact)}
                  class={[
                    "w-full px-4 py-3 text-left flex items-center gap-3 transition-colors",
                    idx == 0 && "bg-indigo-50",
                    idx != 0 && "hover:bg-slate-50"
                  ]}
                >
                  <div class="mention-chip-avatar contact">
                    {get_initials(contact)}
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-sm font-medium text-slate-900 truncate">
                      {contact.display_name || contact[:display_name]}
                    </div>
                    <div class="text-xs text-slate-500 flex items-center gap-1 truncate">
                      <span class={[
                        "inline-block w-2 h-2 rounded-full",
                        get_crm_provider(contact) == "hubspot" && "bg-orange-500",
                        get_crm_provider(contact) == "salesforce" && "bg-blue-500"
                      ]}></span>
                      <span>{contact.email || contact[:email]}</span>
                    </div>
                  </div>
                </button>
              <% end %>
            </div>

            <!-- Mention chips display -->
            <div :if={length(@mention_chips) > 0} class="flex flex-wrap gap-2 mb-3">
              <%= for {chip, idx} <- Enum.with_index(@mention_chips) do %>
                <span class={["mention-chip", chip.type]}>
                  <span class="mention-chip-icon">{chip_icon(chip.type)}</span>
                  <span class="mention-chip-name">{chip.display_name}</span>
                  <button
                    type="button"
                    phx-click="remove_chip"
                    phx-value-index={idx}
                    class="mention-chip-remove"
                  >
                    <.icon name="hero-x-mark" class="h-3 w-3" />
                  </button>
                </span>
              <% end %>
            </div>

            <!-- Input container -->
            <div class="relative rounded-2xl border border-slate-300 bg-white focus-within:ring-2 focus-within:ring-indigo-500 focus-within:border-transparent transition-all">
              <!-- Top toolbar -->
              <div class="px-4 pt-3">
                <button
                  type="button"
                  phx-click="add_context"
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-slate-600 hover:text-slate-900 bg-slate-100 hover:bg-slate-200 rounded-full transition-colors"
                  title="Add context by mentioning a contact"
                >
                  <.icon name="hero-at-symbol" class="h-4 w-4" />
                  <span>Add context</span>
                </button>
              </div>

              <textarea
                id="bubble-chat-input"
                name="message"
                rows="3"
                placeholder="Ask anything about your meetings..."
                phx-keyup="input_change"
                phx-hook="BubbleChatInput"
                phx-update="ignore"
                disabled={@sending}
                class="w-full resize-none border-0 px-4 py-3 text-sm focus:outline-none focus:ring-0 disabled:bg-slate-50 disabled:text-slate-500 placeholder:text-slate-400"
              >{@input_value}</textarea>

              <!-- Bottom toolbar -->
              <div class="flex items-center justify-between px-4 pb-3">
                <div class="flex items-center gap-2">
                  <span class="text-xs text-slate-500">Sources</span>
                  <%= if @hubspot_credential || @salesforce_credential do %>
                    <div class="flex items-center gap-1">
                      <%= if @hubspot_credential do %>
                        <div class="w-5 h-5 rounded-full bg-orange-500 flex items-center justify-center" title="HubSpot">
                          <span class="text-white text-[10px] font-bold">H</span>
                        </div>
                      <% end %>
                      <%= if @salesforce_credential do %>
                        <div class="w-5 h-5 rounded-full bg-blue-500 flex items-center justify-center" title="Salesforce">
                          <span class="text-white text-[10px] font-bold">S</span>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <.link href={~p"/dashboard/settings"} class="text-xs text-indigo-600 hover:underline">Connect</.link>
                  <% end %>
                </div>

                <div class="flex items-center gap-3">
                  <span class="text-xs text-slate-400">⇧↵ to send</span>
                  <button
                    type="button"
                    phx-click="send_message"
                    disabled={@sending || String.trim(@input_value) == ""}
                    class={[
                      "p-2 rounded-xl transition-all",
                      String.trim(@input_value) != "" && !@sending && "bg-indigo-600 text-white hover:bg-indigo-700",
                      (String.trim(@input_value) == "" || @sending) && "bg-slate-200 text-slate-400 cursor-not-allowed"
                    ]}
                  >
                    <.icon name="hero-arrow-up" class="h-5 w-5" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("toggle_bubble", _params, socket) do
    new_state = !socket.assigns.bubble_open

    socket =
      if new_state do
        socket
        |> assign(bubble_open: true)
        |> push_event("focus_bubble_input", %{})
      else
        assign(socket, bubble_open: false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_bubble", _params, socket) do
    {:noreply, assign(socket, bubble_open: false)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    socket =
      socket
      |> assign(
        current_thread: nil,
        messages: %{},
        input_value: "",
        mentions: [],
        mention_chips: [],
        active_tab: :chat
      )
      |> push_event("focus_bubble_input", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_thread", %{"id" => thread_id}, socket) do
    thread = Chat.get_thread_with_messages(thread_id, socket.assigns.current_user.id)

    if thread do
      grouped = Chat.get_messages_grouped_by_date(thread.id)

      {:noreply,
       socket
       |> assign(current_thread: thread, messages: grouped, active_tab: :chat)
       |> push_event("focus_bubble_input", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("input_change", %{"value" => value}, socket) do
    socket = handle_mention_detection(socket, value)
    {:noreply, assign(socket, input_value: value)}
  end

  @impl true
  def handle_event("add_context", _params, socket) do
    new_value =
      case String.trim_trailing(socket.assigns.input_value) do
        "" -> "@"
        val -> val <> " @"
      end

    {:noreply,
     socket
     |> assign(input_value: new_value)
     |> push_event("update_bubble_input", %{value: new_value})
     |> push_event("focus_bubble_input", %{})}
  end

  @impl true
  def handle_event("select_mention", %{"contact" => contact_json}, socket) do
    contact = Jason.decode!(contact_json)

    # Create a mention chip
    chip = %{
      type: :contact,
      id: contact["id"],
      display_name: contact["display_name"],
      crm_provider: contact["crm_provider"],
      email: contact["email"]
    }

    mention = %{
      contact_id: contact["id"],
      contact_name: contact["display_name"],
      crm_provider: contact["crm_provider"]
    }

    # Remove the @query from input
    new_value =
      if socket.assigns.mention_query do
        String.replace(
          socket.assigns.input_value,
          ~r/@#{Regex.escape(socket.assigns.mention_query)}$/,
          ""
        )
      else
        socket.assigns.input_value
      end

    {:noreply,
     socket
     |> assign(
       input_value: new_value,
       mentions: socket.assigns.mentions ++ [mention],
       mention_chips: socket.assigns.mention_chips ++ [chip],
       mention_query: nil,
       mention_search_results: []
     )
     |> push_event("update_bubble_input", %{value: new_value})}
  end

  @impl true
  def handle_event("remove_chip", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    new_chips = List.delete_at(socket.assigns.mention_chips, index)
    new_mentions = List.delete_at(socket.assigns.mentions, index)

    {:noreply, assign(socket, mention_chips: new_chips, mentions: new_mentions)}
  end

  @impl true
  def handle_event("close_mention_dropdown", _params, socket) do
    {:noreply, assign(socket, mention_query: nil, mention_search_results: [])}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    content = socket.assigns.input_value
    mentions = socket.assigns.mentions
    chips = socket.assigns.mention_chips

    # Build the full message content with chip references
    full_content = build_content_with_chips(content, chips)

    cond do
      String.trim(full_content) == "" && Enum.empty?(chips) ->
        {:noreply, socket}

      is_nil(socket.assigns.current_thread) ->
        case Chat.create_thread(%{user_id: socket.assigns.current_user.id}) do
          {:ok, thread} ->
            socket =
              socket
              |> assign(
                current_thread: thread,
                sending: true,
                input_value: "",
                mentions: [],
                mention_chips: [],
                pending_message: full_content
              )
              |> push_event("update_bubble_input", %{value: ""})

            send(self(), {:process_message, thread.id, full_content, mentions})
            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create chat")}
        end

      true ->
        socket =
          socket
          |> assign(
            sending: true,
            input_value: "",
            mentions: [],
            mention_chips: [],
            pending_message: full_content
          )
          |> push_event("update_bubble_input", %{value: ""})

        send(self(), {:process_message, socket.assigns.current_thread.id, full_content, mentions})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, bubble_open: false)}
  end

  @impl true
  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_bubble", _params, socket) do
    {:noreply,
     socket
     |> assign(bubble_open: true)
     |> push_event("focus_bubble_input", %{})}
  end

  # Handle messages

  @impl true
  def handle_info({:process_message, thread_id, content, mentions}, socket) do
    credentials = %{
      hubspot: socket.assigns.hubspot_credential,
      salesforce: socket.assigns.salesforce_credential
    }

    # Start streaming indicator
    socket = assign(socket, streaming: true, streaming_content: "")

    # Create a callback that sends chunks to this process
    liveview_pid = self()
    stream_callback = fn chunk ->
      send(liveview_pid, {:stream_chunk, chunk})
    end

    # Process message with streaming in a Task to not block the LiveView
    Task.start(fn ->
      result = ChatAssistant.process_message_stream(
        thread_id,
        socket.assigns.current_user.id,
        content,
        mentions,
        credentials,
        stream_callback
      )
      send(liveview_pid, {:stream_complete, thread_id, content, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_complete, thread_id, content, result}, socket) do
    case result do
      {:ok, _result} ->
        grouped = Chat.get_messages_grouped_by_date(thread_id)
        threads = Chat.list_user_threads(socket.assigns.current_user.id)

        thread = Chat.get_user_thread(thread_id, socket.assigns.current_user.id)

        thread =
          if is_nil(thread.title) or thread.title == "" do
            title = String.slice(content, 0, 50)
            {:ok, updated} = Chat.update_thread(thread, %{title: title})
            updated
          else
            thread
          end

        {:noreply,
         assign(socket,
           messages: grouped,
           threads: threads,
           current_thread: thread,
           sending: false,
           streaming: false,
           streaming_content: "",
           pending_message: nil
         )}

      {:error, reason} ->
        Logger.error("Chat message processing failed: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Failed to process message. Please try again.")
         |> assign(sending: false, streaming: false, streaming_content: "", pending_message: nil)}
    end
  end

  @impl true
  def handle_info({:search_contacts, query}, socket) do
    credentials = %{
      hubspot: socket.assigns.hubspot_credential,
      salesforce: socket.assigns.salesforce_credential
    }

    {:ok, results} = ChatAssistant.search_contacts(query, credentials)
    {:noreply, assign(socket, mention_search_results: results)}
  end

  @impl true
  def handle_info({:stream_chunk, chunk}, socket) do
    new_content = socket.assigns.streaming_content <> chunk
    {:noreply, assign(socket, streaming_content: new_content)}
  end

  # Private helpers

  defp handle_mention_detection(socket, value) do
    case detect_mention_query(value) do
      {:mention, query} when byte_size(query) >= 2 ->
        send(self(), {:search_contacts, query})
        assign(socket, mention_query: query)

      _ ->
        assign(socket, mention_query: nil, mention_search_results: [])
    end
  end

  defp detect_mention_query(value) do
    case Regex.run(~r/@(\w+)$/, value) do
      [_, query] -> {:mention, query}
      _ -> :none
    end
  end

  defp build_content_with_chips(content, chips) do
    chip_text =
      chips
      |> Enum.map(fn chip -> "@#{chip.display_name}" end)
      |> Enum.join(" ")

    case {String.trim(content), chip_text} do
      {"", ""} -> ""
      {"", chips} -> chips
      {text, ""} -> text
      {text, chips} -> "#{chips} #{text}"
    end
  end

  defp contact_json(contact) do
    Jason.encode!(%{
      id: contact.id || contact[:id],
      display_name: contact.display_name || contact[:display_name],
      crm_provider: contact.crm_provider || contact[:crm_provider],
      email: contact.email || contact[:email],
      firstname: contact.firstname || contact[:firstname],
      lastname: contact.lastname || contact[:lastname]
    })
  end

  defp get_initials(contact) do
    first = contact.firstname || contact[:firstname] || ""
    last = contact.lastname || contact[:lastname] || ""
    "#{String.first(first) || ""}#{String.first(last) || ""}"
  end

  defp get_crm_provider(contact) do
    contact.crm_provider || contact[:crm_provider]
  end

  defp chip_icon(:contact), do: "👤"
  defp chip_icon(:meeting), do: "📅"
  defp chip_icon(:deal), do: "💼"
  defp chip_icon(_), do: "📎"

  defp render_content_with_chips(content, _mentions) do
    content
  end

  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        today = Date.utc_today()

        cond do
          date == today -> "Today"
          date == Date.add(today, -1) -> "Yesterday"
          true -> Calendar.strftime(date, "%b %d")
        end

      _ ->
        date_string
    end
  end

  defp format_thread_time(thread) do
    datetime =
      case thread.chat_messages do
        [msg | _] -> msg.inserted_at
        _ -> thread.inserted_at
      end

    relative_time(datetime)
  end

  defp relative_time(%NaiveDateTime{} = datetime) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, datetime, :second)
    humanize_time(diff, datetime)
  end

  defp relative_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    humanize_time(diff, datetime)
  end

  defp relative_time(_), do: ""

  defp humanize_time(diff, datetime) do
    cond do
      diff < 60 -> "Now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      diff < 604_800 -> "#{div(diff, 86400)}d"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp first_message(thread) do
    List.first(thread.chat_messages)
  end

  defp has_sources?(message) do
    message.sources && message.sources["meetings"] && length(message.sources["meetings"]) > 0
  end
end
