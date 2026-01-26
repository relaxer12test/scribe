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
      salesforce_reauth_required =
        not is_nil(salesforce_credential) and not is_nil(salesforce_credential.reauth_required_at)

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
        |> assign(:searching_contacts, false)
        |> assign(:sending, false)
        |> assign(:pending_message, nil)
        |> assign(:pending_chips, [])
        |> assign(:pending_mentions, [])
        |> assign(:streaming, false)
        |> assign(:streaming_content, "")
        |> assign(:hubspot_credential, hubspot_credential)
        |> assign(:salesforce_credential, salesforce_credential)
        |> assign(:salesforce_reauth_required, salesforce_reauth_required)

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
        class="fixed top-0 right-0 h-full w-full sm:w-[24rem] bg-white border-t border-slate-200 shadow-[0_0_0_1px_rgba(226,232,240,0.9),0_18px_40px_rgba(15,23,42,0.08)] z-50 flex flex-col chat-sidebar-enter"
      >
        <!-- Header -->
        <div class="px-4 pt-4 pb-2 flex items-center justify-between flex-shrink-0">
          <h2 class="text-[15px] font-semibold text-slate-900">
            Ask Anything
          </h2>
          <button
            phx-click="close_bubble"
            class="p-1 text-slate-400 hover:text-slate-500 transition-colors"
            title="Expand"
          >
            <.icon name="hero-chevron-double-right" class="h-4 w-4" />
          </button>
        </div>

        <!-- Tabs -->
        <div class="px-4 pb-2 flex items-center justify-between flex-shrink-0">
          <div class="flex items-center gap-1">
            <button
              phx-click="switch_tab"
              phx-value-tab="chat"
              class={[
                "px-2.5 py-1 text-[12px] rounded-full transition-colors",
                @active_tab == :chat && "font-medium text-slate-700 bg-slate-100",
                @active_tab != :chat && "font-medium text-slate-400 hover:text-slate-600"
              ]}
            >
              Chat
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="history"
              class={[
                "px-2.5 py-1 text-[12px] rounded-full transition-colors",
                @active_tab == :history && "font-medium text-slate-700 bg-slate-100",
                @active_tab != :history && "font-medium text-slate-400 hover:text-slate-600"
              ]}
            >
              History
            </button>
          </div>
          <button
            phx-click="new_chat"
            class="p-1 text-slate-400 hover:text-slate-600 transition-colors"
            title="New conversation"
          >
            <.icon name="hero-plus" class="h-4 w-4" />
          </button>
        </div>

        <%= if @salesforce_reauth_required do %>
          <div class="mx-4 mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 text-amber-900">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p class="text-sm font-semibold">Reconnect Salesforce to keep CRM context in chat</p>
                <p class="text-xs text-amber-800">
                  We couldn't refresh your Salesforce connection. Reconnect to continue using CRM data.
                </p>
              </div>
              <.link
                href={~p"/auth/salesforce?prompt=consent"}
                method="get"
                class="inline-flex items-center justify-center rounded-md bg-amber-600 px-3 py-1.5 text-xs font-semibold text-white shadow hover:bg-amber-700"
              >
                Reconnect Salesforce
              </.link>
            </div>
          </div>
        <% end %>

        <!-- Content Area - scrollable -->
        <div class="flex-1 overflow-y-auto min-h-0">
          <%= if @active_tab == :chat do %>
            <div class="px-4 pb-4 pt-2 space-y-4" id="chat-messages">
              <!-- Welcome message -->
              <%= if is_nil(@current_thread) || map_size(@messages) == 0 do %>
                <div class="max-w-[80%] rounded-2xl bg-slate-100 px-3 py-2 text-[13px] leading-snug text-slate-700">
                  I can answer questions about Jump meetings and data – just ask!
                </div>
              <% else %>
                <!-- Messages grouped by date -->
                <%= for {date, msgs} <- @messages do %>
                  <!-- Date/time divider with side lines -->
                  <div class="flex items-center gap-3 py-2">
                    <div class="flex-1 border-t border-slate-200"></div>
                    <span class="text-[11px] text-slate-400 whitespace-nowrap">
                      {format_date_with_time(date, List.first(msgs))}
                    </span>
                    <div class="flex-1 border-t border-slate-200"></div>
                  </div>

                  <%= for msg <- msgs do %>
                    <%= if msg.role == "user" do %>
                      <!-- User message - gray bubble, right aligned -->
                      <div class="flex justify-end">
                        <div class="max-w-[80%] rounded-2xl bg-slate-100 px-3 py-2 text-slate-700">
                          <p class="text-[13px] leading-snug"><%= render_content_with_inline_mentions(msg.content, msg.mentions) %></p>
                        </div>
                      </div>
                    <% else %>
                      <!-- AI message - no bubble, left aligned -->
                      <div class="max-w-[90%] space-y-2">
                        <div class="text-[13px] text-slate-700 leading-snug">
                          <%= render_content_with_inline_mentions(msg.content, msg.mentions) %>
                        </div>

                        <!-- Sources -->
                        <%= if has_sources?(msg) do %>
                          <div class="flex items-center gap-1.5 pt-1">
                            <span class="text-[11px] font-medium text-slate-400">Sources</span>
                            <%= for source <- msg.sources["meetings"] || [] do %>
                              <.link
                                href={~p"/dashboard/meetings/#{source["meeting_id"]}"}
                                class="inline-flex items-center"
                                title={source["title"]}
                              >
                                <span class="inline-flex items-center justify-center w-4 h-4 rounded-full bg-slate-800">
                                  <.icon name="hero-video-camera" class="h-2 w-2 text-white" />
                                </span>
                              </.link>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>
                <% end %>
              <% end %>

              <!-- Pending message (user's message while sending) -->
              <div :if={@sending && @pending_message} class="flex justify-end">
                <div class="max-w-[80%] rounded-2xl bg-slate-100 px-3 py-2 text-slate-700">
                  <p class="text-[13px] leading-snug">
                    <%= render_content_with_inline_mentions(@pending_message, @pending_mentions) %>
                  </p>
                </div>
              </div>

              <!-- Streaming response -->
              <div :if={@streaming} class="space-y-2">
                <div class="text-[13px] text-slate-700 leading-snug">
                  {@streaming_content}<span class="streaming-cursor">▌</span>
                </div>
              </div>

              <!-- Thinking indicator (non-streaming) -->
              <div :if={@sending && !@streaming} class="text-[12px] text-slate-500">
                Thinking...
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
        <div class="p-4 bg-white flex-shrink-0">
          <div class="relative">
            <!-- Searching indicator -->
            <div
              :if={@mention_query && @searching_contacts && length(@mention_search_results) == 0}
              id="bubble-mention-loading"
              class="absolute bottom-full left-0 mb-2 w-full bg-white rounded-xl shadow-lg border border-slate-200 py-4 z-10"
            >
              <div class="flex items-center justify-center gap-2 text-slate-500 text-sm">
                <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" />
                <span>Searching contacts...</span>
              </div>
            </div>

            <!-- Mention autocomplete dropdown -->
            <div
              :if={@mention_query && length(@mention_search_results) > 0}
              id="bubble-mention-dropdown"
              class="absolute bottom-full left-0 mb-2 w-full bg-white rounded-xl shadow-lg border border-slate-200 max-h-48 overflow-y-auto z-10"
            >
              <%= for {contact, idx} <- Enum.with_index(@mention_search_results) do %>
                <div
                  data-mention-item
                  data-contact={contact_json(contact)}
                  class={[
                    "w-full px-4 py-2.5 text-left flex items-center gap-2.5 transition-colors cursor-pointer",
                    idx == 0 && "bg-slate-50",
                    idx != 0 && "hover:bg-slate-50"
                  ]}
                >
                  <!-- Avatar with provider badge -->
                  <div class="relative flex-shrink-0">
                    <div class="w-7 h-7 rounded-full bg-slate-200 flex items-center justify-center text-slate-600 text-xs font-medium">
                      {get_initials(contact)}
                    </div>
                    <!-- Provider badge -->
                    <div class={[
                      "absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 rounded-full flex items-center justify-center text-[8px] font-bold text-white border border-white",
                      get_crm_provider(contact) == "hubspot" && "bg-orange-500",
                      get_crm_provider(contact) == "salesforce" && "bg-blue-500"
                    ]}>
                      {provider_letter(get_crm_provider(contact))}
                    </div>
                  </div>
                  <span class="text-sm text-slate-700 truncate">
                    {contact.display_name || contact[:display_name]}
                  </span>
                </div>
              <% end %>
            </div>

            <!-- Input container -->
            <div class="relative rounded-2xl border border-slate-300 bg-white focus-within:border-blue-500 transition-colors">
              <!-- Top toolbar with Add context -->
              <div class="px-3 pt-3">
                <button
                  type="button"
                  phx-click="add_context"
                  class="inline-flex items-center gap-1.5 rounded-full bg-slate-100 px-2.5 py-1 text-[12px] text-slate-600 hover:bg-slate-200 transition-colors"
                  title="Add context by mentioning a contact"
                >
                  <span class="flex h-4 w-4 items-center justify-center rounded-full bg-white text-[10px] font-semibold text-slate-500 shadow-sm">@</span>
                  <span>Add context</span>
                </button>
              </div>

              <!-- Contenteditable input with inline mentions -->
              <div
                id="bubble-chat-input"
                contenteditable={if @sending, do: "false", else: "true"}
                phx-hook="BubbleChatInput"
                phx-update="ignore"
                data-placeholder="Ask anything about your meetings"
                data-mentions={Jason.encode!(@mention_chips)}
                class={[
                  "chat-input-editable w-full min-h-[2.75rem] max-h-32 overflow-y-auto px-3 py-2 text-[13px] leading-snug focus:outline-none",
                  @sending && "bg-slate-50 text-slate-500 pointer-events-none"
                ]}
              ></div>

              <!-- Bottom toolbar -->
              <div class="flex items-center justify-between px-3 pb-3">
                <div class="flex items-center gap-1.5">
                  <span class="text-[11px] text-slate-400">Sources</span>
                  <%= if @hubspot_credential || @salesforce_credential do %>
                    <div class="flex items-center gap-1">
                      <!-- CRM connections only -->
                      <%= if @hubspot_credential do %>
                        <div class="relative group">
                          <div class="w-4 h-4 rounded-full bg-orange-500 flex items-center justify-center">
                            <span class="text-white text-[8px] font-bold">H</span>
                          </div>
                          <span class="pointer-events-none absolute bottom-full left-1/2 -translate-x-1/2 mb-1.5 rounded bg-slate-900 px-1.5 py-0.5 text-[10px] font-medium text-white opacity-0 transition-opacity group-hover:opacity-100 whitespace-nowrap">
                            HubSpot
                          </span>
                        </div>
                      <% end %>
                      <%= if @salesforce_credential do %>
                        <div class="relative group">
                          <div class="w-4 h-4 rounded-full bg-blue-500 flex items-center justify-center">
                            <span class="text-white text-[8px] font-bold">S</span>
                          </div>
                          <span class="pointer-events-none absolute bottom-full left-1/2 -translate-x-1/2 mb-1.5 rounded bg-slate-900 px-1.5 py-0.5 text-[10px] font-medium text-white opacity-0 transition-opacity group-hover:opacity-100 whitespace-nowrap">
                            Salesforce
                          </span>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <.link href={~p"/dashboard/settings"} class="text-[11px] text-indigo-600 hover:underline">Connect</.link>
                  <% end %>
                </div>

                <button
                  type="button"
                  phx-click="send_message"
                  disabled={@sending}
                  class={[
                    "h-7 w-7 rounded-full flex items-center justify-center transition-colors",
                    !@sending && "bg-slate-100 text-slate-400 hover:bg-slate-200 hover:text-slate-600",
                    @sending && "bg-slate-100 text-slate-300 cursor-not-allowed"
                  ]}
                >
                  <.icon name="hero-arrow-up" class="h-4 w-4" />
                </button>
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

    {:noreply, push_chat_url_state(socket)}
  end

  @impl true
  def handle_event("close_bubble", _params, socket) do
    socket =
      socket
      |> assign(bubble_open: false)
      |> push_chat_url_state()

    {:noreply, socket}
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
        pending_chips: [],
        pending_mentions: [],
        active_tab: :chat
      )
      |> push_event("focus_bubble_input", %{})
      |> push_chat_url_state()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_thread", %{"id" => thread_id}, socket) do
    thread = Chat.get_thread_with_messages(thread_id, socket.assigns.current_user.id)

    if thread do
      grouped = Chat.get_messages_grouped_by_date(thread.id, socket.assigns.current_user.id)

      {:noreply,
       socket
       |> assign(current_thread: thread, messages: grouped, active_tab: :chat)
       |> push_event("focus_bubble_input", %{})
       |> push_chat_url_state()}
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
  def handle_event("select_mention", params, socket) do
    # JS inserts the pill directly, we just need to close dropdown and track mentions
    # Mentions come from JS as JSON string
    mentions =
      case params["mentions"] do
        nil -> socket.assigns.mentions
        json ->
          case Jason.decode(json) do
            {:ok, list} -> Enum.map(list, fn m -> %{
              contact_id: m["contact_id"],
              contact_name: m["contact_name"],
              crm_provider: m["crm_provider"]
            } end)
            _ -> socket.assigns.mentions
          end
      end

    {:noreply,
     socket
     |> assign(
       mentions: mentions,
       mention_query: nil,
       mention_search_results: [],
       searching_contacts: false
     )}
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
    {:noreply, assign(socket, mention_query: nil, mention_search_results: [], searching_contacts: false)}
  end

  @impl true
  def handle_event("mention_inserted", params, socket) do
    # JS has inserted a mention pill, update our mentions list
    mentions =
      case params["mentions"] do
        nil -> socket.assigns.mentions
        json ->
          case Jason.decode(json) do
            {:ok, list} -> Enum.map(list, fn m -> %{
              contact_id: m["contact_id"],
              contact_name: m["contact_name"],
              crm_provider: m["crm_provider"]
            } end)
            _ -> socket.assigns.mentions
          end
      end

    {:noreply, assign(socket, mentions: mentions)}
  end

  @impl true
  def handle_event("send_message", params, socket) do
    # Content and mentions come from JS hook (contenteditable)
    content = params["content"] || socket.assigns.input_value
    mentions_json = params["mentions"]

    mentions =
      if mentions_json do
        case Jason.decode(mentions_json) do
          {:ok, list} -> Enum.map(list, fn m -> %{
            contact_id: m["contact_id"],
            contact_name: m["contact_name"],
            crm_provider: m["crm_provider"]
          } end)
          _ -> socket.assigns.mentions
        end
      else
        socket.assigns.mentions
      end

    cond do
      String.trim(content) == "" && Enum.empty?(mentions) ->
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
                pending_chips: [],
                mention_chips: [],
                pending_message: content,
                pending_mentions: mentions
              )
              |> push_event("update_bubble_input", %{value: ""})
              |> push_chat_url_state()

            send(self(), {:process_message, thread.id, content, mentions})
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
            pending_chips: [],
            mention_chips: [],
            pending_message: content,
            pending_mentions: mentions
          )
          |> push_event("update_bubble_input", %{value: ""})

        send(self(), {:process_message, socket.assigns.current_thread.id, content, mentions})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    socket =
      socket
      |> assign(bubble_open: false)
      |> push_chat_url_state()

    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_bubble", _params, socket) do
    socket =
      socket
      |> assign(bubble_open: true)
      |> push_event("focus_bubble_input", %{})
      |> push_chat_url_state()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sync_url_state", params, socket) do
    open = parse_open_param(params["open"])
    thread_id = params["thread_id"]

    socket =
      socket
      |> assign(bubble_open: open)
      |> maybe_assign_thread(thread_id)

    socket =
      if open do
        push_event(socket, "focus_bubble_input", %{})
      else
        socket
      end

    {:noreply, push_chat_url_state(socket)}
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
        grouped = Chat.get_messages_grouped_by_date(thread_id, socket.assigns.current_user.id)
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
           pending_message: nil,
           pending_chips: [],
           pending_mentions: [],
           salesforce_reauth_required: socket.assigns.salesforce_reauth_required
         )}

      {:error, {:reauth_required, _info}} ->
        {:noreply,
         socket
         |> assign(
           sending: false,
           streaming: false,
           streaming_content: "",
           pending_message: nil,
           pending_chips: [],
           pending_mentions: [],
           salesforce_reauth_required: true
         )
         |> put_flash(:error, "Reconnect Salesforce to keep CRM context in chat.")}

      {:error, reason} ->
        Logger.error("Chat message processing failed: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Failed to process message. Please try again.")
         |> assign(
           sending: false,
           streaming: false,
           streaming_content: "",
           pending_message: nil,
           pending_chips: [],
           pending_mentions: []
         )}
    end
  end

  @impl true
  def handle_info({:search_contacts, query}, socket) do
    credentials = %{
      hubspot: socket.assigns.hubspot_credential,
      salesforce: socket.assigns.salesforce_credential
    }

    {:ok, results, errors} = ChatAssistant.search_contacts(query, credentials)
    salesforce_reauth_required = match?({:reauth_required, _}, errors.salesforce)

    {:noreply,
     assign(socket,
       mention_search_results: results,
       searching_contacts: false,
       salesforce_reauth_required: salesforce_reauth_required
     )}
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
        assign(socket, mention_query: query, searching_contacts: true)

      _ ->
        assign(socket, mention_query: nil, mention_search_results: [], searching_contacts: false)
    end
  end

  defp parse_open_param(value) when value in [true, "true", "1", 1, "open", "yes"], do: true
  defp parse_open_param(value) when value in [false, "false", "0", 0, "closed", "no", nil], do: false
  defp parse_open_param(_value), do: false

  defp maybe_assign_thread(socket, nil) do
    assign(socket, current_thread: nil, messages: %{})
  end

  defp maybe_assign_thread(socket, "") do
    assign(socket, current_thread: nil, messages: %{})
  end

  defp maybe_assign_thread(socket, thread_id) do
    thread = Chat.get_thread_with_messages(thread_id, socket.assigns.current_user.id)

    if thread do
      grouped = Chat.get_messages_grouped_by_date(thread.id, socket.assigns.current_user.id)
      assign(socket, current_thread: thread, messages: grouped, active_tab: :chat)
    else
      assign(socket, current_thread: nil, messages: %{})
    end
  end

  defp push_chat_url_state(socket) do
    thread_id = socket.assigns.current_thread && socket.assigns.current_thread.id
    push_event(socket, "chat_url_state", %{open: socket.assigns.bubble_open, thread_id: thread_id})
  end

  defp detect_mention_query(value) do
    case Regex.run(~r/@(\w+)$/, value) do
      [_, query] -> {:mention, query}
      _ -> :none
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

  defp provider_letter("hubspot"), do: "H"
  defp provider_letter("salesforce"), do: "S"
  defp provider_letter(_), do: ""

  # Render message content with inline mention pills.
  defp render_content_with_inline_mentions(content, mentions) when is_list(mentions) and length(mentions) > 0 do
    escaped_content =
      content
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    {with_placeholders, replacements} =
      mentions
      |> normalize_mentions()
      |> Enum.with_index()
      |> Enum.reduce({escaped_content, []}, fn {mention, idx}, {acc, replacements} ->
        {updated, replacement} = replace_mention_with_placeholder(acc, mention, idx)
        replacements =
          case replacement do
            nil -> replacements
            _ -> [replacement | replacements]
          end

        {updated, replacements}
      end)

    rendered =
      replacements
      |> Enum.reverse()
      |> Enum.reduce(with_placeholders, fn {placeholder, pill_html}, acc ->
        String.replace(acc, placeholder, pill_html)
      end)

    Phoenix.HTML.raw(rendered)
  end
  defp render_content_with_inline_mentions(content, _), do: content

  defp normalize_mentions(mentions) do
    normalized =
      mentions
      |> Enum.map(fn mention ->
        %{
          name: mention.contact_name || mention[:contact_name] || "",
          provider: mention.crm_provider || mention[:crm_provider] || ""
        }
      end)
      |> Enum.map(fn mention -> %{mention | name: String.trim(mention.name)} end)
      |> Enum.filter(fn mention -> mention.name != "" end)
      |> Enum.uniq_by(fn mention -> String.downcase(mention.name) end)

    first_counts = name_part_counts(normalized, :first)
    last_counts = name_part_counts(normalized, :last)

    normalized
    |> Enum.map(fn mention ->
      {first, last} = mention_name_parts(mention.name)
      variants =
        mention_variants(mention.name, first, last, first_counts, last_counts)
        |> Enum.sort_by(&String.length/1, :desc)
      Map.put(mention, :variants, variants)
    end)
    |> Enum.sort_by(fn mention -> String.length(mention.name) end, :desc)
  end

  defp replace_mention_with_placeholder(content, %{name: name, provider: provider} = mention, idx) do
    variants =
      mention
      |> Map.get(:variants, mention_name_variants(name))
      |> Enum.sort_by(&String.length/1, :desc)

    case variants do
      [] ->
        {content, nil}

      _ ->
        pattern =
          variants
          |> Enum.map(fn variant ->
            variant
            |> Phoenix.HTML.html_escape()
            |> Phoenix.HTML.safe_to_string()
            |> Regex.escape()
          end)
          |> Enum.join("|")

        placeholder = "__MENTION_PILL_#{idx}__"
        regex = Regex.compile!("(?:@(?:#{pattern})|\\b(?:#{pattern})\\b)(?!@)", "i")
        updated = Regex.replace(regex, content, placeholder)
        {updated, {placeholder, mention_pill_html(name, provider)}}
    end
  end

  defp mention_name_variants(name) when is_binary(name) and name != "" do
    [name]
  end
  defp mention_name_variants(_), do: []

  defp mention_name_parts(name) do
    parts = String.split(name, ~r/\s+/, trim: true)

    case parts do
      [] -> {"", ""}
      [single] -> {single, single}
      _ -> {List.first(parts), List.last(parts)}
    end
  end

  defp mention_variants(full, first, last, first_counts, last_counts) do
    variants = [full]

    variants =
      if first != "" and Map.get(first_counts, String.downcase(first), 0) == 1 do
        [first | variants]
      else
        variants
      end

    variants =
      if last != "" and last != first and Map.get(last_counts, String.downcase(last), 0) == 1 do
        [last | variants]
      else
        variants
      end

    Enum.uniq(variants)
  end

  defp name_part_counts(mentions, part) do
    mentions
    |> Enum.map(fn mention ->
      {first, last} = mention_name_parts(mention.name)
      case part do
        :first -> first
        :last -> last
      end
    end)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.frequencies()
  end

  defp mention_pill_html(name, provider) do
    safe_name = Phoenix.HTML.html_escape(name) |> Phoenix.HTML.safe_to_string()
    safe_initials = Phoenix.HTML.html_escape(get_mention_initials(name)) |> Phoenix.HTML.safe_to_string()
    safe_provider = Phoenix.HTML.html_escape(provider_letter(provider)) |> Phoenix.HTML.safe_to_string()

    badge_class =
      case provider do
        "hubspot" -> "bg-orange-500"
        "salesforce" -> "bg-blue-500"
        _ -> ""
      end

    badge_classes =
      if badge_class == "" do
        "inline-mention-pill-badge"
      else
        "inline-mention-pill-badge #{badge_class}"
      end

    "<span class=\"inline-mention-pill inline-mention-pill--message\"><span class=\"inline-mention-pill-avatar\">#{safe_initials}<span class=\"#{badge_classes}\">#{safe_provider}</span></span><span class=\"inline-mention-pill-name\">#{safe_name}</span></span>"
  end

  defp get_mention_initials(name) when is_binary(name) do
    parts = String.split(name, " ", trim: true)
    case parts do
      [first | [last | _]] -> "#{String.first(first) || ""}#{String.first(last) || ""}"
      [first | _] -> String.first(first) || ""
      _ -> ""
    end
  end
  defp get_mention_initials(_), do: ""

  defp format_date_with_time(date_string, first_msg) do
    time_str =
      case first_msg do
        %{inserted_at: %NaiveDateTime{} = dt} ->
          hour = dt.hour
          minute = dt.minute
          am_pm = if hour >= 12, do: "pm", else: "am"
          display_hour = cond do
            hour == 0 -> 12
            hour > 12 -> hour - 12
            true -> hour
          end
          "#{display_hour}:#{String.pad_leading(Integer.to_string(minute), 2, "0")}#{am_pm}"
        _ -> ""
      end

    date_str =
      case Date.from_iso8601(date_string) do
        {:ok, date} ->
          Calendar.strftime(date, "%B %d, %Y")
        _ ->
          date_string
      end

    if time_str != "" do
      "#{time_str} – #{date_str}"
    else
      date_str
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
