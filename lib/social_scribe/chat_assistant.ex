defmodule SocialScribe.ChatAssistant do
  @moduledoc """
  Orchestrates chat interactions with AI, CRM data, and meeting context.
  """

  alias SocialScribe.Chat
  alias SocialScribe.Meetings
  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi

  require Logger

  @doc """
  Process a user message and generate AI response.

  Takes a thread_id, user_id, message content, list of mentions, and CRM credentials.
  Creates the user message, fetches context, calls AI, and saves the assistant response.
  """
  def process_message(thread_id, user_id, content, mentions, credentials) do
    with {:ok, user_message} <- Chat.create_user_message(thread_id, content, format_mentions(mentions)),
         {:ok, context} <- build_context(user_id, mentions, credentials),
         history <- get_conversation_history(thread_id, user_id),
         {:ok, ai_response} <-
           AIContentGeneratorApi.generate_chat_response(
             content,
             context.contacts,
             context.meetings,
             history
           ),
         {:ok, assistant_message} <-
           Chat.create_assistant_message(
             thread_id,
             ai_response.answer,
             %{"meetings" => ai_response.sources}
           ) do
      {:ok, %{user_message: user_message, assistant_message: assistant_message}}
    end
  end

  @doc """
  Process a user message with streaming AI response.

  Similar to process_message/5 but streams the response via callback.
  The callback receives text chunks as they arrive.
  """
  def process_message_stream(thread_id, user_id, content, mentions, credentials, stream_callback) do
    with {:ok, user_message} <- Chat.create_user_message(thread_id, content, format_mentions(mentions)),
         {:ok, context} <- build_context(user_id, mentions, credentials),
         history <- get_conversation_history(thread_id, user_id),
         {:ok, ai_response} <-
           AIContentGeneratorApi.generate_chat_response_stream(
             content,
             context.contacts,
             context.meetings,
             history,
             stream_callback
           ),
         {:ok, assistant_message} <-
           Chat.create_assistant_message(
             thread_id,
             ai_response.answer,
             %{"meetings" => ai_response.sources}
           ) do
      {:ok, %{user_message: user_message, assistant_message: assistant_message}}
    end
  end

  @doc """
  Search contacts across connected CRMs.

  Returns a combined list of contacts from HubSpot and/or Salesforce,
  each tagged with their crm_provider.
  """
  def search_contacts(query, credentials) do
    Logger.info("[ChatAssistant] Searching contacts for query: #{inspect(query)}")
    results = []

    results =
      if credentials.hubspot do
        Logger.info("[ChatAssistant] Querying HubSpot for: #{inspect(query)}")

        case HubspotApi.search_contacts(credentials.hubspot, query) do
          {:ok, contacts} ->
            Logger.info("[ChatAssistant] HubSpot returned #{length(contacts)} contacts: #{inspect(Enum.map(contacts, & &1.email))}")

            tagged =
              Enum.map(contacts, fn c ->
                c
                |> Map.put(:crm_provider, "hubspot")
                |> Map.put(:display_name, "#{c.firstname} #{c.lastname}")
              end)

            results ++ tagged

          {:error, reason} ->
            Logger.warning("[ChatAssistant] HubSpot search failed: #{inspect(reason)}")
            results
        end
      else
        Logger.debug("[ChatAssistant] HubSpot not connected, skipping")
        results
      end

    results =
      if credentials.salesforce do
        Logger.info("[ChatAssistant] Querying Salesforce for: #{inspect(query)}")

        case SalesforceApi.search_contacts(credentials.salesforce, query) do
          {:ok, contacts} ->
            Logger.info("[ChatAssistant] Salesforce returned #{length(contacts)} contacts: #{inspect(Enum.map(contacts, & &1.email))}")

            tagged =
              Enum.map(contacts, fn c ->
                c
                |> Map.put(:crm_provider, "salesforce")
                |> Map.put(:display_name, "#{c.firstname} #{c.lastname}")
              end)

            results ++ tagged

          {:error, reason} ->
            Logger.warning("[ChatAssistant] Salesforce search failed: #{inspect(reason)}")
            results
        end
      else
        Logger.debug("[ChatAssistant] Salesforce not connected, skipping")
        results
      end

    Logger.info("[ChatAssistant] Total results: #{length(results)}")
    {:ok, results}
  end

  # Private functions

  defp format_mentions(mentions) when is_list(mentions) do
    Enum.map(mentions, fn mention ->
      %{
        contact_id: mention[:contact_id] || mention["contact_id"],
        contact_name: mention[:contact_name] || mention["contact_name"],
        crm_provider: mention[:crm_provider] || mention["crm_provider"]
      }
    end)
  end

  defp format_mentions(_), do: []

  defp build_context(user_id, mentions, credentials) do
    contacts = fetch_mentioned_contacts(mentions, credentials)
    meetings = fetch_relevant_meetings(user_id, contacts)
    {:ok, %{contacts: contacts, meetings: meetings}}
  end

  defp fetch_mentioned_contacts(mentions, credentials) do
    mentions
    |> Enum.map(fn mention ->
      provider = mention[:crm_provider] || mention["crm_provider"]
      contact_id = mention[:contact_id] || mention["contact_id"]

      case provider do
        "hubspot" when not is_nil(credentials.hubspot) ->
          case HubspotApi.get_contact(credentials.hubspot, contact_id) do
            {:ok, contact} -> Map.put(contact, :crm_provider, "hubspot")
            _ -> nil
          end

        "salesforce" when not is_nil(credentials.salesforce) ->
          case SalesforceApi.get_contact(credentials.salesforce, contact_id) do
            {:ok, contact} -> Map.put(contact, :crm_provider, "salesforce")
            _ -> nil
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_relevant_meetings(user_id, _contacts) do
    # Get recent meetings for the user
    # If contacts are mentioned, we could filter by participant names
    # For now, get the most recent meetings with transcripts
    meetings = Meetings.list_user_meetings(%{id: user_id})

    # Filter to meetings that have transcripts and limit to recent ones
    meetings
    |> Enum.filter(fn m -> m.meeting_transcript != nil end)
    |> Enum.take(5)
  end

  defp get_conversation_history(thread_id, user_id) do
    case Chat.get_thread_with_messages(thread_id, user_id) do
      nil ->
        []

      thread ->
        thread.chat_messages
        |> Enum.take(-10)
        |> Enum.map(fn msg ->
          %{role: msg.role, content: msg.content}
        end)
    end
  end
end
