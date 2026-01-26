defmodule SocialScribe.ChatAssistant do
  @moduledoc """
  Orchestrates chat interactions with AI, CRM data, and meeting context.
  """

  alias SocialScribe.Chat
  alias SocialScribe.Meetings
  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.CrmUpdates
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi

  require Logger

  @doc """
  Process a user message and generate AI response.

  Takes a thread_id, user_id, message content, list of mentions, and CRM credentials.
  Creates the user message, fetches context, calls AI, and saves the assistant response.
  """
  def process_message(thread_id, user_id, content, mentions, credentials) do
    formatted_mentions = format_mentions(mentions)

    case Chat.get_user_thread(thread_id, user_id) do
      nil ->
        {:error, :unauthorized}

      _thread ->
        with {:ok, user_message} <- Chat.create_user_message(thread_id, content, formatted_mentions),
             {:ok, context} <- build_context(user_id, formatted_mentions, credentials),
             history <- get_conversation_history(thread_id, user_id),
             {:ok, ai_response} <-
               AIContentGeneratorApi.generate_chat_response(
                 content,
                 context.contacts,
                 context.meetings,
                 context.updates,
                 history
               ),
             {:ok, assistant_message} <-
               Chat.create_assistant_message(
                 thread_id,
                 ai_response.answer,
                 %{"meetings" => ai_response.sources},
                 mentions_referenced_in_content(formatted_mentions, ai_response.answer)
               ) do
          {:ok, %{user_message: user_message, assistant_message: assistant_message}}
        end
    end
  end

  @doc """
  Process a user message with streaming AI response.

  Similar to process_message/5 but streams the response via callback.
  The callback receives text chunks as they arrive.
  """
  def process_message_stream(thread_id, user_id, content, mentions, credentials, stream_callback) do
    formatted_mentions = format_mentions(mentions)

    case Chat.get_user_thread(thread_id, user_id) do
      nil ->
        {:error, :unauthorized}

      _thread ->
        with {:ok, user_message} <- Chat.create_user_message(thread_id, content, formatted_mentions),
             {:ok, context} <- build_context(user_id, formatted_mentions, credentials),
             history <- get_conversation_history(thread_id, user_id),
             {:ok, ai_response} <-
               AIContentGeneratorApi.generate_chat_response_stream(
                 content,
                 context.contacts,
                 context.meetings,
                 context.updates,
                 history,
                 stream_callback
               ),
             {:ok, assistant_message} <-
               Chat.create_assistant_message(
                 thread_id,
                 ai_response.answer,
                 %{"meetings" => ai_response.sources},
                 mentions_referenced_in_content(formatted_mentions, ai_response.answer)
               ) do
          {:ok, %{user_message: user_message, assistant_message: assistant_message}}
        end
    end
  end

  @doc """
  Search contacts across connected CRMs.

  Returns a combined list of contacts from HubSpot and/or Salesforce,
  each tagged with their crm_provider, plus an errors map for per-CRM failures.
  """
  def search_contacts(query, credentials) do
    Logger.info("[ChatAssistant] Searching contacts for query: #{inspect(query)}")
    results = []
    errors = %{hubspot: nil, salesforce: nil}

    {results, errors} =
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

            {results ++ tagged, errors}

          {:error, reason} ->
            Logger.warning("[ChatAssistant] HubSpot search failed: #{inspect(reason)}")
            {results, Map.put(errors, :hubspot, reason)}
        end
      else
        Logger.debug("[ChatAssistant] HubSpot not connected, skipping")
        {results, errors}
      end

    {results, errors} =
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

            {results ++ tagged, errors}

          {:error, reason} ->
            Logger.warning("[ChatAssistant] Salesforce search failed: #{inspect(reason)}")
            {results, Map.put(errors, :salesforce, reason)}
        end
      else
        Logger.debug("[ChatAssistant] Salesforce not connected, skipping")
        {results, errors}
      end

    Logger.info("[ChatAssistant] Total results: #{length(results)}")
    {:ok, results, errors}
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

  defp mentions_referenced_in_content(mentions, content)
       when is_list(mentions) and is_binary(content) do
    mentions
    |> normalize_mentions_for_matching()
    |> Enum.filter(fn mention ->
      mention_variants_in_content?(content, mention.variants)
    end)
    |> Enum.map(&Map.drop(&1, [:variants]))
  end

  defp mentions_referenced_in_content(_, _), do: []

  defp mention_variants_in_content?(content, variants) do
    case variants do
      [] ->
        false

      _ ->
        pattern =
          variants
          |> Enum.map(&Regex.escape/1)
          |> Enum.join("|")

        regex = Regex.compile!("(?:@(?:#{pattern})|\\b(?:#{pattern})\\b)(?!@)", "i")
        Regex.match?(regex, content)
    end
  end

  defp normalize_mentions_for_matching(mentions) do
    normalized =
      mentions
      |> Enum.map(fn mention ->
        %{
          contact_id: mention[:contact_id] || mention["contact_id"],
          contact_name: mention[:contact_name] || mention["contact_name"] || "",
          crm_provider: mention[:crm_provider] || mention["crm_provider"]
        }
      end)
      |> Enum.map(fn mention -> %{mention | contact_name: String.trim(mention.contact_name)} end)
      |> Enum.filter(fn mention -> mention.contact_name != "" end)
      |> Enum.uniq_by(fn mention -> String.downcase(mention.contact_name) end)

    first_counts = name_part_counts(normalized, :first)
    last_counts = name_part_counts(normalized, :last)

    normalized
    |> Enum.map(fn mention ->
      name = mention.contact_name
      {first, last} = mention_name_parts(name)
      variants = mention_variants(name, first, last, first_counts, last_counts)
      Map.put(mention, :variants, variants)
    end)
  end

  defp name_part_counts(mentions, part) do
    mentions
    |> Enum.map(fn mention ->
      name = mention.contact_name
      {first, last} = mention_name_parts(name)

      case part do
        :first -> first
        :last -> last
      end
    end)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.frequencies()
  end

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

  defp build_context(user_id, mentions, credentials) do
    with {:ok, contacts} <- fetch_mentioned_contacts(mentions, credentials) do
      meetings = fetch_relevant_meetings(user_id, contacts)
      updates = fetch_relevant_updates(meetings, contacts)
      {:ok, %{contacts: contacts, meetings: meetings, updates: updates}}
    end
  end

  defp fetch_mentioned_contacts(mentions, credentials) do
    mentions
    |> Enum.reduce_while({:ok, []}, fn mention, {:ok, acc} ->
      provider = mention[:crm_provider] || mention["crm_provider"]
      contact_id = mention[:contact_id] || mention["contact_id"]

      case provider do
        "hubspot" when not is_nil(credentials.hubspot) ->
          case HubspotApi.get_contact(credentials.hubspot, contact_id) do
            {:ok, contact} ->
              {:cont, {:ok, [Map.put(contact, :crm_provider, "hubspot") | acc]}}

            _ ->
              {:cont, {:ok, acc}}
          end

        "salesforce" when not is_nil(credentials.salesforce) ->
          case SalesforceApi.get_contact(credentials.salesforce, contact_id) do
            {:ok, contact} ->
              {:cont, {:ok, [Map.put(contact, :crm_provider, "salesforce") | acc]}}

            {:error, {:reauth_required, _info} = reason} ->
              {:halt, {:error, reason}}

            _ ->
              {:cont, {:ok, acc}}
          end

        _ ->
          {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, contacts} -> {:ok, Enum.reverse(contacts)}
      {:error, _reason} = error -> error
    end
  end

  defp fetch_relevant_meetings(user_id, contacts) do
    meetings =
      Meetings.list_user_meetings(%{id: user_id})
      |> Enum.filter(&meeting_has_transcript?/1)

    tokens = contact_match_tokens(contacts)

    meetings =
      if Enum.empty?(tokens) do
        meetings
      else
        Enum.filter(meetings, &meeting_mentions_tokens?(&1, tokens))
      end

    Enum.take(meetings, 5)
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

  defp fetch_relevant_updates(meetings, contacts) do
    meeting_ids = Enum.map(meetings, & &1.id)

    meeting_ids
    |> CrmUpdates.list_updates_for_meetings()
    |> filter_updates_for_contacts(contacts)
  end

  defp filter_updates_for_contacts(updates, []), do: updates

  defp filter_updates_for_contacts(updates, contacts) do
    allowed =
      contacts
      |> Enum.map(&contact_key/1)
      |> MapSet.new()

    Enum.filter(updates, fn update ->
      MapSet.member?(allowed, {update.crm_provider, update.contact_id})
    end)
  end

  defp contact_key(contact) do
    provider = contact[:crm_provider] || contact["crm_provider"]
    id = contact[:id] || contact["id"] || contact[:contact_id] || contact["contact_id"]
    {provider, id && to_string(id)}
  end

  defp contact_match_tokens([]), do: []

  defp contact_match_tokens(contacts) do
    contacts
    |> Enum.flat_map(&contact_tokens/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.uniq()
  end

  defp contact_tokens(contact) do
    firstname = contact[:firstname] || contact["firstname"]
    lastname = contact[:lastname] || contact["lastname"]
    display_name = contact[:display_name] || contact["display_name"]
    email = contact[:email] || contact["email"]

    full_name =
      cond do
        present?(display_name) -> display_name
        present?(firstname) or present?(lastname) -> String.trim("#{firstname || ""} #{lastname || ""}")
        true -> nil
      end

    [full_name, email, firstname, lastname]
    |> Enum.filter(&present?/1)
  end

  defp meeting_has_transcript?(%{meeting_transcript: %{content: %{"data" => data}}})
       when is_list(data),
       do: data != []

  defp meeting_has_transcript?(%{meeting_transcript: %{content: content}}) when is_binary(content),
    do: String.trim(content) != ""

  defp meeting_has_transcript?(_), do: false

  defp meeting_mentions_tokens?(meeting, tokens) do
    participant_match? =
      (meeting.meeting_participants || [])
      |> Enum.map(&String.downcase(&1.name || ""))
      |> Enum.any?(fn name -> Enum.any?(tokens, &String.contains?(name, &1)) end)

    participant_match? ||
      transcript_mentions_tokens?(meeting.meeting_transcript, tokens, meeting.meeting_participants)
  end

  defp transcript_mentions_tokens?(%{content: %{"data" => data}}, tokens, participants)
       when is_list(data) do
    Enum.any?(data, &segment_mentions_tokens?(&1, tokens, participants))
  end

  defp transcript_mentions_tokens?(%{content: data}, tokens, participants) when is_list(data) do
    Enum.any?(data, &segment_mentions_tokens?(&1, tokens, participants))
  end

  defp transcript_mentions_tokens?(_transcript, _tokens, _participants), do: false

  defp segment_mentions_tokens?(segment, tokens, participants) do
    speaker = Meetings.resolve_speaker_name(segment, participants, "")
    words = Map.get(segment, "words", [])
    text = Enum.map_join(words, " ", &Map.get(&1, "text", ""))
    haystack = String.downcase("#{speaker} #{text}")
    Enum.any?(tokens, &String.contains?(haystack, &1))
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
