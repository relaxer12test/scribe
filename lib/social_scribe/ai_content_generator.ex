defmodule SocialScribe.AIContentGenerator do
  @moduledoc "Generates content using Google Gemini."

  @behaviour SocialScribe.AIContentGeneratorApi

  alias SocialScribe.Meetings
  alias SocialScribe.Automations

  @gemini_model "gemini-2.0-flash-lite"
  @gemini_api_base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl SocialScribe.AIContentGeneratorApi
  def generate_follow_up_email(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        Based on the following meeting transcript, please draft a concise and professional follow-up email.
        The email should summarize the key discussion points and clearly list any action items assigned, including who is responsible if mentioned.
        Keep the tone friendly and action-oriented.

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_automation(automation, meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        #{Automations.generate_prompt_for_automation(automation)}

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_hubspot_suggestions(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        You are an AI assistant that extracts contact information updates from meeting transcripts.

        Analyze the following meeting transcript and extract any information that could be used to update a CRM contact record.

        Look for mentions of:
        - Phone numbers (phone, mobilephone)
        - Email addresses (email)
        - Company name (company)
        - Job title/role (jobtitle)
        - Physical address details (address, city, state, zip, country)
        - Website URLs (website)
        - LinkedIn profile (linkedin_url)
        - Twitter handle (twitter_handle)

        IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

        The transcript includes timestamps in [MM:SS] format at the start of each line.

        Return your response as a JSON array of objects. Each object should have:
        - "field": the CRM field name (use exactly: firstname, lastname, email, phone, mobilephone, company, jobtitle, address, city, state, zip, country, website, linkedin_url, twitter_handle)
        - "value": the extracted value
        - "person": the full name of the person this update applies to, if explicitly mentioned; otherwise null
        - "context": a brief quote of where this was mentioned
        - "timestamp": the timestamp in MM:SS format where this was mentioned

        If no contact information updates are found, return an empty array: []

        Example response format:
        [
          {"field": "phone", "value": "555-123-4567", "person": "John Doe", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
          {"field": "company", "value": "Acme Corp", "person": "Sarah Lee", "context": "Sarah said she just joined Acme Corp", "timestamp": "05:47"}
        ]

        ONLY return valid JSON, no other text.

        Meeting transcript:
        #{meeting_prompt}
        """

        case call_gemini(prompt) do
          {:ok, response} ->
            parse_hubspot_suggestions(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_salesforce_suggestions(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        You are an AI assistant that extracts contact information updates from meeting transcripts.

        Analyze the following meeting transcript and extract any information that could be used to update a Salesforce Contact record.

        Look for mentions of:
        - Phone numbers (Phone, MobilePhone)
        - Email addresses (Email)
        - Job title/role (Title)
        - Physical address details (MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry)
        - First and last names (FirstName, LastName)

        IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

        The transcript includes timestamps in [MM:SS] format at the start of each line.

        Return your response as a JSON array of objects. Each object should have:
        - "field": the Salesforce Contact field name (use exactly: FirstName, LastName, Email, Phone, MobilePhone, Title, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry)
        - "value": the extracted value
        - "person": the full name of the person this update applies to, if explicitly mentioned; otherwise null
        - "context": a brief quote of where this was mentioned
        - "timestamp": the timestamp in MM:SS format where this was mentioned

        If no contact information updates are found, return an empty array: []

        Example response format:
        [
          {"field": "Phone", "value": "555-123-4567", "person": "John Doe", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
          {"field": "Title", "value": "VP of Operations", "person": "Sarah Lee", "context": "Sarah said she is the VP of Operations", "timestamp": "05:47"}
        ]

        ONLY return valid JSON, no other text.

        Meeting transcript:
        #{meeting_prompt}
        """

        case call_gemini(prompt) do
          {:ok, response} ->
            parse_salesforce_suggestions(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp parse_hubspot_suggestions(response) do
    parse_contact_suggestions(response)
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_chat_response(
        user_query,
        mentioned_contacts,
        meeting_context,
        crm_updates,
        conversation_history
      ) do
    prompt =
      build_chat_prompt(user_query, mentioned_contacts, meeting_context, crm_updates, conversation_history)

    case call_gemini(prompt) do
      {:ok, response} ->
        parse_chat_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_chat_response_stream(
        user_query,
        mentioned_contacts,
        meeting_context,
        crm_updates,
        conversation_history,
        callback
      ) do
    prompt =
      build_chat_prompt_simple(
        user_query,
        mentioned_contacts,
        meeting_context,
        crm_updates,
        conversation_history
      )

    case call_gemini(prompt) do
      {:ok, response} ->
        # Simulate streaming by sending words progressively
        simulate_streaming(response, callback)
        {:ok, %{answer: response, sources: []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_chat_prompt_simple(user_query, contacts, meetings, crm_updates, history) do
    """
    You are an AI assistant that answers questions about CRM contacts and meeting data.
    You help users understand their meetings and contact information from their CRM (HubSpot or Salesforce).

    ## Contact Information
    #{format_contacts_for_prompt(contacts)}

    ## CRM Updates
    #{format_updates_for_prompt(crm_updates)}

    ## Meeting Context
    #{format_meetings_for_prompt(meetings, contacts)}

    ## Conversation History
    #{format_history_for_prompt(history)}

    ## Current Question
    #{user_query}

    Instructions:
    - Answer the user's question based on the contact information and meeting context provided
    - "Action taken" means a CRM update was applied from a meeting suggestion; use CRM Updates to confirm
    - Be specific and reference the actual data when possible
    - If you reference information from a meeting, mention the meeting title
    - If you don't have enough information to answer, say so clearly
    - Respond in plain text (not JSON), be concise and helpful
    """
  end

  defp simulate_streaming(text, callback) do
    # Split text into words and send them progressively
    words = String.split(text, ~r/(\s+)/, include_captures: true)

    Enum.each(words, fn word ->
      callback.(word)
      # Small delay between words for visual effect
      Process.sleep(20)
    end)
  end

  defp build_chat_prompt(user_query, contacts, meetings, crm_updates, history) do
    """
    You are an AI assistant that answers questions about CRM contacts and meeting data.
    You help users understand their meetings and contact information from their CRM (HubSpot or Salesforce).

    ## Contact Information
    #{format_contacts_for_prompt(contacts)}

    ## CRM Updates
    #{format_updates_for_prompt(crm_updates)}

    ## Meeting Context
    #{format_meetings_for_prompt(meetings, contacts)}

    ## Conversation History
    #{format_history_for_prompt(history)}

    ## Current Question
    #{user_query}

    Instructions:
    - Answer the user's question based on the contact information and meeting context provided
    - "Action taken" means a CRM update was applied from a meeting suggestion; use CRM Updates to confirm
    - Be specific and reference the actual data when possible
    - If you reference information from a meeting, include the meeting title and timestamp in your response
    - If you don't have enough information to answer, say so clearly

    Respond in JSON format:
    {
      "answer": "Your detailed response here",
      "sources": [
        {"meeting_id": 123, "title": "Meeting Title", "timestamp": "01:23", "quote": "relevant quote from transcript"}
      ]
    }

    The "sources" array should only include meetings that you actually referenced in your answer.
    If no meetings were referenced, use an empty array: []

    ONLY return valid JSON, no other text.
    """
  end

  defp format_contacts_for_prompt([]), do: "No contacts mentioned."

  defp format_contacts_for_prompt(contacts) do
    contacts
    |> Enum.map(fn contact ->
      """
      - #{contact[:firstname] || contact["firstname"]} #{contact[:lastname] || contact["lastname"]} (#{contact[:crm_provider] || contact["crm_provider"]})
        Email: #{contact[:email] || contact["email"] || "N/A"}
        Phone: #{contact[:phone] || contact["phone"] || "N/A"}
        Company: #{contact[:company] || contact["company"] || "N/A"}
        Title: #{contact[:jobtitle] || contact[:title] || contact["jobtitle"] || contact["title"] || "N/A"}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_updates_for_prompt([]), do: "No CRM updates have been applied from meetings."

  defp format_updates_for_prompt(updates) do
    updates
    |> Enum.take(10)
    |> Enum.map(fn update ->
      meeting = update.meeting || %{}
      meeting_title = Map.get(meeting, :title) || "Unknown meeting"
      meeting_id = update.meeting_id || Map.get(meeting, :id)
      contact = update.contact_name || update.contact_id || "Unknown contact"
      applied_at = format_datetime(update.applied_at)
      updates_text = format_update_fields(update.updates)

      """
      - Meeting: #{meeting_title} (ID: #{meeting_id})
        CRM: #{String.capitalize(update.crm_provider)} Contact: #{contact}
        Applied at: #{applied_at}
        Updates: #{updates_text}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_update_fields(updates) when is_map(updates) do
    updates
    |> Enum.map(fn {field, value} ->
      "#{field}: #{format_update_value(value)}"
    end)
    |> Enum.join("; ")
  end

  defp format_update_fields(_), do: "No updates recorded"

  defp format_update_value(value) when is_binary(value), do: value
  defp format_update_value(nil), do: "nil"
  defp format_update_value(value), do: to_string(value)

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp format_datetime(_), do: "unknown time"

  defp format_meetings_for_prompt([], _contacts), do: "No meeting context available."

  defp format_meetings_for_prompt(meetings, contacts) do
    tokens = contact_match_tokens(contacts)

    meetings
    |> Enum.take(5)
    |> Enum.map(fn meeting ->
      transcript =
        case meeting.meeting_transcript do
          nil -> "No transcript available"
          t -> format_transcript_excerpt(t.content, tokens, meeting.meeting_participants)
        end

      """
      Meeting ID: #{meeting.id}
      Title: #{meeting.title}
      Date: #{meeting.recorded_at}
      Participants: #{format_participants(meeting.meeting_participants)}
      Transcript excerpt:
      #{transcript}
      ---
      """
    end)
    |> Enum.join("\n")
  end

  defp format_transcript_excerpt(nil, _tokens, _participants), do: "No transcript"

  defp format_transcript_excerpt(%{"data" => data}, tokens, participants) when is_list(data) do
    format_transcript_excerpt(data, tokens, participants)
  end

  defp format_transcript_excerpt(content, tokens, participants) when is_list(content) do
    segments =
      if Enum.empty?(tokens) do
        Enum.take(content, 20)
      else
        matched = Enum.filter(content, &segment_mentions_tokens?(&1, tokens, participants))
        if matched == [], do: Enum.take(content, 20), else: Enum.take(matched, 20)
      end

    segments
    |> Enum.map(fn segment ->
      speaker = Meetings.resolve_speaker_name(segment, participants, "Unknown")
      words = Map.get(segment, "words", [])
      text = Enum.map_join(words, " ", &Map.get(&1, "text", ""))
      timestamp = format_timestamp(List.first(words))
      "[#{timestamp}] #{speaker}: #{text}"
    end)
    |> Enum.join("\n")
  end

  defp format_transcript_excerpt(content, _tokens, _participants) when is_binary(content) do
    content |> String.slice(0, 2000)
  end

  defp format_transcript_excerpt(_content, _tokens, _participants), do: "No transcript"

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

  defp segment_mentions_tokens?(segment, tokens, participants) do
    speaker = Meetings.resolve_speaker_name(segment, participants, "")
    words = Map.get(segment, "words", [])
    text = Enum.map_join(words, " ", &Map.get(&1, "text", ""))
    haystack = String.downcase("#{speaker} #{text}")
    Enum.any?(tokens, &String.contains?(haystack, &1))
  end

  defp format_timestamp(nil), do: "00:00"

  defp format_timestamp(word) do
    seconds = extract_seconds(Map.get(word, "start_timestamp"))
    total_seconds = trunc(seconds)
    minutes = div(total_seconds, 60)
    secs = rem(total_seconds, 60)
    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp extract_seconds(%{"relative" => relative}) when is_number(relative), do: relative
  defp extract_seconds(seconds) when is_number(seconds), do: seconds
  defp extract_seconds(_), do: 0

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp format_participants(nil), do: "Unknown"
  defp format_participants([]), do: "Unknown"

  defp format_participants(participants) do
    participants
    |> Enum.map(fn p -> p.name end)
    |> Enum.join(", ")
  end

  defp format_history_for_prompt([]), do: "This is the start of the conversation."

  defp format_history_for_prompt(history) do
    history
    |> Enum.take(-10)
    |> Enum.map(fn msg ->
      role = msg[:role] || msg["role"]
      content = msg[:content] || msg["content"]
      "#{String.capitalize(role)}: #{content}"
    end)
    |> Enum.join("\n\n")
  end

  defp parse_chat_response(response) do
    cleaned = strip_json_fences(response)

    case Jason.decode(cleaned) do
      {:ok, %{"answer" => answer, "sources" => sources}} when is_list(sources) ->
        {:ok, %{answer: answer, sources: sources}}

      {:ok, %{"answer" => answer}} ->
        {:ok, %{answer: answer, sources: []}}

      {:ok, _} ->
        # If structure is unexpected, use the raw cleaned response
        {:ok, %{answer: cleaned, sources: []}}

      {:error, _} ->
        # If JSON parsing fails, return the raw response
        {:ok, %{answer: cleaned, sources: []}}
    end
  end

  defp parse_salesforce_suggestions(response) do
    parse_contact_suggestions(response)
  end

  defp parse_contact_suggestions(response) do
    cleaned = strip_json_fences(response)

    case Jason.decode(cleaned) do
      {:ok, suggestions} when is_list(suggestions) ->
        formatted =
          suggestions
          |> Enum.filter(&is_map/1)
          |> Enum.map(&format_contact_suggestion/1)
          |> Enum.filter(fn s -> s.field != nil and s.value != nil end)

        {:ok, formatted}

      {:ok, _} ->
        {:ok, []}

      {:error, _} ->
        {:ok, []}
    end
  end

  defp format_contact_suggestion(suggestion) do
    %{
      field: suggestion["field"],
      value: suggestion["value"],
      person: suggestion["person"],
      context: suggestion["context"],
      timestamp: suggestion["timestamp"]
    }
  end

  defp strip_json_fences(response) do
    response
    |> String.trim()
    |> String.replace(~r/^```json\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()
  end

  defp call_gemini(prompt_text) do
    api_key = Application.get_env(:social_scribe, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, {:config_error, "Gemini API key is missing - set GEMINI_API_KEY env var"}}
    else
      path = "/#{@gemini_model}:generateContent?key=#{api_key}"

      payload = %{
        contents: [
          %{
            parts: [%{text: prompt_text}]
          }
        ]
      }

      case Tesla.post(client(), path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          text_path = [
            "candidates",
            Access.at(0),
            "content",
            "parts",
            Access.at(0),
            "text"
          ]

          case get_in(body, text_path) do
            nil -> {:error, {:parsing_error, "No text content found in Gemini response", body}}
            text_content -> {:ok, text_content}
          end

        {:ok, %Tesla.Env{status: status, body: error_body}} ->
          {:error, {:api_error, status, error_body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @gemini_api_base_url},
      Tesla.Middleware.JSON
    ])
  end
end
