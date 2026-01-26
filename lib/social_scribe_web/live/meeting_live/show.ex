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
  def mount(%{"id" => meeting_id}, _session, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)

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
              error: "Failed to search contacts: #{inspect(reason)}",
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
              error: "Failed to generate suggestions: #{inspect(reason)}",
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
              error: "Failed to update contact: #{inspect(reason)}",
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
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <div :for={segment <- @meeting_transcript.content["data"]} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                {segment["speaker"] || "Unknown Speaker"}:
              </span>
              {Enum.map_join(segment["words"] || [], " ", & &1["text"])}
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
