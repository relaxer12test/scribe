defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton
  import SocialScribeWeb.ModalComponents, only: [hubspot_modal: 1, crm_provider_icon: 1]

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.CrmProviders
  alias SocialScribe.CrmUpdates

  @impl true
  def mount(%{"id" => meeting_id}, session, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)
    timezone = normalize_timezone(session["browser_timezone"])

    user_has_automations =
      Automations.list_active_user_automations(socket.assigns.current_user.id)
      |> length()
      |> Kernel.>(0)

    automation_results = Automations.list_automation_results_for_meeting(meeting_id)

    if meeting.calendar_event.user_id != socket.assigns.current_user.id do
      socket =
        socket
        |> put_flash(:error, "You do not have permission to view this meeting.")
        |> redirect(to: ~p"/dashboard/meetings")

      {:error, socket}
    else
      crm_providers = CrmProviders.providers()

      crm_credentials =
        crm_providers
        |> Enum.map(fn provider ->
          {provider.id, Accounts.get_user_credential(socket.assigns.current_user, provider.id)}
        end)
        |> Enum.into(%{})

      crm_integrations =
        crm_providers
        |> Enum.map(fn provider -> %{provider: provider, credential: Map.get(crm_credentials, provider.id)} end)
        |> Enum.filter(& &1.credential)

      socket =
        socket
        |> assign(:page_title, "Meeting Details: #{meeting.title}")
        |> assign(:meeting, meeting)
        |> assign(:automation_results, automation_results)
        |> assign(:user_has_automations, user_has_automations)
        |> assign(:crm_credentials, crm_credentials)
        |> assign(:crm_integrations, crm_integrations)
        |> assign(:crm_modal, nil)
        |> assign(:timezone, timezone)
        |> assign(
          :follow_up_email_form,
          to_form(%{
            "follow_up_email" => ""
          })
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"automation_result_id" => automation_result_id}, _uri, socket) do
    automation_result = Automations.get_automation_result!(automation_result_id)
    automation = Automations.get_automation!(automation_result.automation_id)

    socket =
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)
      |> assign(:crm_modal, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_params(%{"provider" => provider_id}, _uri, %{assigns: %{live_action: :crm}} = socket) do
    case CrmProviders.fetch(provider_id) do
      {:ok, provider} ->
        credential = Map.get(socket.assigns.crm_credentials, provider.id)

        if credential do
          {:noreply, assign(socket, crm_modal: %{provider: provider, credential: credential})}
        else
          {:noreply,
           socket
           |> assign(:crm_modal, nil)
           |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")}
        end

      :error ->
        {:noreply,
         socket
         |> assign(:crm_modal, nil)
         |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, crm_modal: nil)}
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:crm_search, provider_id, query, credential}, socket) do
    case CrmProviders.fetch(provider_id) do
      {:ok, provider} ->
        modal_id = CrmProviders.modal_id(provider)

        case CrmProviders.search_contacts(provider, credential, query) do
          {:ok, contacts} ->
            send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
              id: modal_id,
              contacts: contacts,
              searching: false,
              reauth_required: false
            )

          {:error, {:reauth_required, _info}} ->
            send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
              id: modal_id,
              contacts: [],
              searching: false,
              reauth_required: true,
              error: "Reconnect #{provider.name} to search contacts."
            )

          {:error, reason} ->
            send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
              id: modal_id,
              error: crm_error_message(provider, :search, reason),
              searching: false,
              reauth_required: false
            )
        end

      :error ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:crm_generate_suggestions, provider_id, contact, meeting, credential}, socket) do
    case CrmProviders.fetch(provider_id) do
      {:ok, provider} ->
        modal_id = CrmProviders.modal_id(provider)

        case CrmProviders.generate_suggestions(provider, credential, contact, meeting) do
          {:ok, %{contact: updated_contact, suggestions: suggestions}} ->
            send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
              id: modal_id,
              step: :suggestions,
              selected_contact: updated_contact,
              suggestions: suggestions,
              loading: false,
              reauth_required: false
            )

          {:error, {:reauth_required, _info}} ->
            send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
              id: modal_id,
              error: "Reconnect #{provider.name} to generate suggestions.",
              loading: false,
              reauth_required: true
            )

          {:error, reason} ->
            send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
              id: modal_id,
              error: crm_error_message(provider, :suggestions, reason),
              loading: false,
              reauth_required: false
            )
        end

      :error ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:crm_apply_updates, provider_id, updates, contact, credential}, socket) do
    case CrmProviders.fetch(provider_id) do
      {:ok, provider} ->
        modal_id = CrmProviders.modal_id(provider)

        case CrmProviders.apply_updates(provider, credential, contact, updates) do
          {:ok, _updated_contact} ->
            record_crm_update(socket, provider.id, contact, updates)

            socket =
              socket
              |> put_flash(
                :info,
                "Successfully updated #{map_size(updates)} field(s) in #{provider.name}"
              )
              |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

            {:noreply, socket}

          {:error, {:reauth_required, _info}} ->
            send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
              id: modal_id,
              error: "Reconnect #{provider.name} to apply updates.",
              loading: false,
              reauth_required: true
            )

            {:noreply, socket}

          {:error, reason} ->
            send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
              id: modal_id,
              error: crm_error_message(provider, :update, reason),
              loading: false,
              reauth_required: false
            )

            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  defp record_crm_update(socket, provider, contact, updates) when map_size(updates) > 0 do
    contact_id = Map.get(contact, :id) || Map.get(contact, "id")

    if contact_id do
      CrmUpdates.create_contact_update(%{
        meeting_id: socket.assigns.meeting.id,
        crm_provider: provider,
        contact_id: to_string(contact_id),
        contact_name: contact_display_name(contact),
        updates: updates,
        status: "applied",
        applied_at: DateTime.utc_now()
      })
    end
  end

  defp record_crm_update(_socket, _provider, _contact, _updates), do: :ok

  defp crm_error_message(provider, action, reason) do
    base =
      case action do
        :search -> "Failed to search contacts in #{provider.name}."
        :suggestions -> "Failed to generate suggestions in #{provider.name}."
        :update -> "Failed to update contact in #{provider.name}."
        _ -> "Failed to complete the request in #{provider.name}."
      end

    detail = crm_error_detail(provider, action, reason) || generic_action_detail(action)

    if detail do
      base <> " " <> detail
    else
      base
    end
  end

  defp crm_error_detail(_provider, _action, :missing_contact_id) do
    "Please select a contact and try again."
  end

  defp crm_error_detail(%{id: "salesforce"}, :update, :missing_country_for_state) do
    "Add a country/territory before setting Mailing State/Province."
  end

  defp crm_error_detail(_provider, _action, :not_found) do
    "That contact was not found."
  end

  defp crm_error_detail(provider, _action, {:http_error, _reason}) do
    "#{provider.name} didn't respond. Please try again."
  end

  defp crm_error_detail(provider, _action, {:token_refresh_failed, _reason}) do
    "We couldn't refresh your #{provider.name} connection. Please reconnect and try again."
  end

  defp crm_error_detail(%{id: "salesforce"}, :update, {:api_error, _status, body}) do
    salesforce_update_error_detail(body)
  end

  defp crm_error_detail(_provider, _action, _reason), do: nil

  defp generic_action_detail(action) do
    case action do
      :update -> "Please review the field values and try again."
      _ -> "Please try again."
    end
  end

  defp salesforce_update_error_detail(body) do
    errors = salesforce_errors(body)

    cond do
      state_requires_country?(errors) ->
        "Add a country/territory before setting Mailing State/Province."

      message = salesforce_first_message(errors) ->
        salesforce_message_for_user(message)

      true ->
        nil
    end
  end

  defp salesforce_errors(body) when is_list(body), do: body
  defp salesforce_errors(body) when is_map(body), do: [body]
  defp salesforce_errors(_body), do: []

  defp state_requires_country?(errors) do
    Enum.any?(errors, fn error ->
      error_code = Map.get(error, "errorCode")
      fields = Map.get(error, "fields", [])
      message = Map.get(error, "message", "")

      error_code == "FIELD_INTEGRITY_EXCEPTION" &&
        "MailingState" in List.wrap(fields) &&
        String.contains?(
          String.downcase(message),
          "country/territory must be specified before specifying a state"
        )
    end)
  end

  defp salesforce_first_message(errors) do
    errors
    |> Enum.map(&Map.get(&1, "message"))
    |> Enum.find(&is_binary/1)
  end

  defp salesforce_message_for_user(message) when is_binary(message) do
    case Regex.run(~r/"([^"]+)"/, message) do
      [_, quoted] -> quoted
      _ -> message
    end
  end

  defp contact_display_name(contact) do
    display_name = Map.get(contact, :display_name) || Map.get(contact, "display_name")
    firstname = Map.get(contact, :firstname) || Map.get(contact, "firstname")
    lastname = Map.get(contact, :lastname) || Map.get(contact, "lastname")
    email = Map.get(contact, :email) || Map.get(contact, "email")

    cond do
      is_binary(display_name) and String.trim(display_name) != "" ->
        String.trim(display_name)

      is_binary(firstname) or is_binary(lastname) ->
        String.trim("#{firstname || ""} #{lastname || ""}")

      is_binary(email) ->
        email

      true ->
        nil
    end
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  defp format_meeting_time(nil, _timezone), do: "N/A"

  defp format_meeting_time(%DateTime{} = datetime, timezone) do
    datetime
    |> shift_to_timezone(timezone)
    |> Timex.format!("%m/%d/%Y, %H:%M:%S", :strftime)
  end

  defp format_meeting_time(datetime, _timezone), do: to_string(datetime)

  defp normalize_timezone(timezone) when is_binary(timezone) do
    case Timex.Timezone.get(timezone, DateTime.utc_now()) do
      %Timex.TimezoneInfo{} -> timezone
      %Timex.AmbiguousTimezoneInfo{} -> timezone
      _ -> "Etc/UTC"
    end
  end

  defp normalize_timezone(_timezone), do: "Etc/UTC"

  defp shift_to_timezone(%DateTime{} = datetime, timezone) when is_binary(timezone) do
    case Timex.Timezone.convert(datetime, timezone) do
      %Timex.AmbiguousDateTime{before: before} -> before
      %DateTime{} = converted -> converted
      {:error, _} -> datetime
    end
  end

  defp shift_to_timezone(datetime, _timezone), do: datetime

  attr :meeting_transcript, :map, required: true

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        Map.get(assigns.meeting_transcript.content, "data") &&
        Enum.any?(Map.get(assigns.meeting_transcript.content, "data"))

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div
        id="meeting-transcript"
        phx-hook="TranscriptHighlight"
        class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2"
      >
        <%= if @has_transcript do %>
          <%= for {segment, index} <- Enum.with_index(@meeting_transcript.content["data"]) do %>
            <% timestamp = segment_timestamp(segment) %>
            <% speaker = segment["speaker"] || "Unknown Speaker" %>
            <% text = Enum.map_join(segment["words"] || [], " ", & &1["text"]) %>
            <div
              id={"transcript-segment-#{index}"}
              data-timestamp={timestamp}
              class="mb-3 transcript-segment"
            >
              <p class="flex gap-3">
                <span class="transcript-timestamp text-xs font-mono text-slate-500 w-14 shrink-0">
                  {timestamp}
                </span>
                <span>
                  <span class="font-semibold text-indigo-600">
                    {speaker}:
                  </span>
                  {text}
                </span>
              </p>
            </div>
          <% end %>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp segment_timestamp(segment) when is_map(segment) do
    words = Map.get(segment, "words", [])
    format_timestamp(List.first(words))
  end

  defp segment_timestamp(_), do: "00:00"

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
end
