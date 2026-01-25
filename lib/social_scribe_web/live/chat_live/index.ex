defmodule SocialScribeWeb.ChatLive.Index do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Chat
  alias SocialScribe.ChatAssistant
  alias SocialScribe.Accounts

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    hubspot_credential = Accounts.get_user_hubspot_credential(user.id)
    salesforce_credential = Accounts.get_user_credential(user, "salesforce")
    salesforce_reauth_required =
      not is_nil(salesforce_credential) and not is_nil(salesforce_credential.reauth_required_at)

    socket =
      socket
      |> assign(:page_title, "Ask Anything")
      |> assign(:threads, Chat.list_user_threads(user.id))
      |> assign(:current_thread, nil)
      |> assign(:messages, %{})
      |> assign(:active_tab, :chat)
      |> assign(:chat_open, false)
      |> assign(:input_value, "")
      |> assign(:mentions, [])
      |> assign(:mention_search_results, [])
      |> assign(:mention_query, nil)
      |> assign(:sending, false)
      |> assign(:pending_message, nil)
      |> assign(:hubspot_credential, hubspot_credential)
      |> assign(:salesforce_credential, salesforce_credential)
      |> assign(:salesforce_reauth_required, salesforce_reauth_required)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"thread_id" => thread_id}, _uri, socket) do
    thread = Chat.get_thread_with_messages(thread_id, socket.assigns.current_user.id)

    if thread do
      grouped = Chat.get_messages_grouped_by_date(thread.id)
      {:noreply,
       socket
       |> assign(current_thread: thread, messages: grouped, active_tab: :chat, chat_open: true)
       |> push_event("focus_chat_input", %{})}
    else
      {:noreply, push_navigate(socket, to: ~p"/dashboard/chat")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_chat", _params, socket) do
    {:noreply,
     socket
     |> assign(chat_open: true, active_tab: :chat)
     |> push_event("focus_chat_input", %{})}
  end

  @impl true
  def handle_event("close_chat", _params, socket) do
    {:noreply, assign(socket, chat_open: false)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("seed_prompt", %{"prompt" => prompt}, socket) do
    {:noreply,
     socket
     |> assign(input_value: prompt, chat_open: true, active_tab: :chat)
     |> push_event("update_chat_input", %{value: prompt})}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    case Chat.create_thread(%{user_id: socket.assigns.current_user.id}) do
      {:ok, thread} ->
        {:noreply, push_patch(socket, to: ~p"/dashboard/chat/#{thread.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create new chat")}
    end
  end

  @impl true
  def handle_event("select_thread", %{"id" => thread_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/chat/#{thread_id}")}
  end

  @impl true
  def handle_event("input_change", %{"value" => value}, socket) do
    socket = handle_mention_detection(socket, value)
    {:noreply, assign(socket, input_value: value)}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    content = socket.assigns.input_value
    mentions = socket.assigns.mentions

    cond do
      String.trim(content) == "" ->
        {:noreply, socket}

      is_nil(socket.assigns.current_thread) ->
        # Create a new thread first
        case Chat.create_thread(%{user_id: socket.assigns.current_user.id}) do
          {:ok, thread} ->
            socket =
              socket
              |> assign(current_thread: thread, sending: true, input_value: "", mentions: [], pending_message: content)
              |> push_event("update_chat_input", %{value: ""})

            send(self(), {:process_message, thread.id, content, mentions})
            {:noreply, push_patch(socket, to: ~p"/dashboard/chat/#{thread.id}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create chat")}
        end

      true ->
        socket =
          socket
          |> assign(sending: true, input_value: "", mentions: [], pending_message: content)
          |> push_event("update_chat_input", %{value: ""})

        send(self(), {:process_message, socket.assigns.current_thread.id, content, mentions})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_mention", %{"contact" => contact_json}, socket) do
    contact = Jason.decode!(contact_json)

    mention = %{
      contact_id: contact["id"],
      contact_name: contact["display_name"],
      crm_provider: contact["crm_provider"]
    }

    # Insert mention into input - replace @query with @Name
    new_value =
      if socket.assigns.mention_query do
        String.replace(
          socket.assigns.input_value,
          ~r/@#{Regex.escape(socket.assigns.mention_query)}$/,
          "@#{contact["display_name"]} "
        )
      else
        socket.assigns.input_value <> "@#{contact["display_name"]} "
      end

    {:noreply,
     socket
     |> assign(
       input_value: new_value,
       mentions: socket.assigns.mentions ++ [mention],
       mention_query: nil,
       mention_search_results: []
     )
     |> push_event("update_chat_input", %{value: new_value})}
  end

  @impl true
  def handle_event("close_mention_dropdown", _params, socket) do
    {:noreply, assign(socket, mention_query: nil, mention_search_results: [])}
  end

  @impl true
  def handle_event("add_context", _params, socket) do
    # Append @ to the input value and focus the input
    new_value =
      case String.trim_trailing(socket.assigns.input_value) do
        "" -> "@"
        val -> val <> " @"
      end

    {:noreply,
     socket
     |> assign(input_value: new_value)
     |> push_event("focus_chat_input", %{})}
  end

  @impl true
  def handle_info({:process_message, thread_id, content, mentions}, socket) do
    credentials = %{
      hubspot: socket.assigns.hubspot_credential,
      salesforce: socket.assigns.salesforce_credential
    }

    case ChatAssistant.process_message(
           thread_id,
           socket.assigns.current_user.id,
           content,
           mentions,
           credentials
         ) do
      {:ok, _result} ->
        grouped = Chat.get_messages_grouped_by_date(thread_id)
        threads = Chat.list_user_threads(socket.assigns.current_user.id)

        # Update thread title if it's the first message
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
           pending_message: nil,
           salesforce_reauth_required: socket.assigns.salesforce_reauth_required
         )}

      {:error, {:reauth_required, _info}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Reconnect Salesforce to keep CRM context in chat.")
         |> assign(sending: false, pending_message: nil, salesforce_reauth_required: true)}

      {:error, reason} ->
        Logger.error("Chat message processing failed: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Failed to process message. Please try again.")
         |> assign(sending: false, pending_message: nil)}
    end
  end

  @impl true
  def handle_info({:mention_search_results, results}, socket) do
    {:noreply, assign(socket, mention_search_results: results)}
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
       salesforce_reauth_required: salesforce_reauth_required
     )}
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

  # Template helper functions

  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        today = Date.utc_today()

        cond do
          date == today -> "Today"
          date == Date.add(today, -1) -> "Yesterday"
          true -> Calendar.strftime(date, "%B %d, %Y")
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
    humanize_relative_time(diff, datetime)
  end

  defp relative_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    humanize_relative_time(diff, datetime)
  end

  defp relative_time(_), do: ""

  defp humanize_relative_time(diff, datetime) do
    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp first_message(thread) do
    List.first(thread.chat_messages)
  end

  defp has_sources?(message) do
    message.sources && message.sources["meetings"] && length(message.sources["meetings"]) > 0
  end

  defp render_content_with_mentions(content, _mentions) do
    # For now, just return the content as-is
    # Mentions are displayed inline in the text as @Name
    content
  end
end
