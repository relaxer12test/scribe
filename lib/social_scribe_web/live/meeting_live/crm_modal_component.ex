defmodule SocialScribeWeb.MeetingLive.CrmModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents
  alias SocialScribe.CrmProviders

  @impl true
  def render(assigns) do
    provider =
      assigns
      |> Map.get(:provider, CrmProviders.default_provider_id())
      |> CrmProviders.normalize_provider()

    provider_config = CrmProviders.get(provider)

    assigns =
      assigns
      |> assign(:provider, provider)
      |> assign(:provider_config, provider_config)
      |> assign(:patch, ~p"/dashboard/meetings/#{assigns.meeting}")
      |> assign_new(:modal_id, fn -> CrmProviders.modal_wrapper_id(provider) end)

    ~H"""
    <div class="space-y-6">
      <%= if @provider_config.reauth && @reauth_required do %>
        <div class="rounded-lg border border-amber-200 bg-amber-50 p-4 text-amber-900 shadow-sm">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p class="font-semibold">Reconnect {@provider_config.name} to continue</p>
              <p class="text-sm text-amber-800">
                We couldn't refresh your {@provider_config.name} connection. Reconnect to keep updates working.
              </p>
            </div>
            <.link
              href={@provider_config.reauth_path}
              method="get"
              class="inline-flex items-center justify-center rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-amber-700"
            >
              Reconnect {@provider_config.name}
            </.link>
          </div>
        </div>
      <% end %>
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">
          Update in {@provider_config.name}
        </h2>
        <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
          Here are suggested updates to sync with your integrations based on this
          <span class="block">meeting</span>
        </p>
      </div>

      <.contact_select
        selected_contact={@selected_contact}
        contacts={@contacts}
        loading={@searching}
        open={@dropdown_open}
        query={@query}
        target={@myself}
        error={@error}
      />

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
          meeting_path={@patch}
          provider_config={@provider_config}
          selected_contact={@selected_contact}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true
  attr :meeting_path, :string, required: true
  attr :provider_config, :map, required: true
  attr :selected_contact, :map, required: true

  defp suggestions_section(assigns) do
    selected_count = Enum.count(assigns.suggestions, & &1.apply)

    info_text =
      if selected_count == 0 do
        "Select the fields you want to update."
      else
        "1 contact, #{selected_count} field(s) selected to update"
      end

    assigns =
      assigns
      |> assign(:selected_count, selected_count)
      |> assign(:field_options, assigns.provider_config.suggestions_module.field_options())
      |> assign(:info_text, info_text)

    ~H"""
    <div class="space-y-4">
      <%= if @loading do %>
        <div class="text-center py-8 text-slate-500">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin mx-auto mb-2" />
          <p>Generating suggestions...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@suggestions) do %>
          <.empty_state
            message="No update suggestions found from this meeting."
            submessage="The AI didn't detect any new contact information in the transcript."
          />
        <% else %>
          <form phx-submit="apply_updates" phx-change="toggle_suggestion" phx-target={@myself}>
            <div class="space-y-4 max-h-[60vh] overflow-y-auto pr-2">
              <.suggestion_card
                :for={suggestion <- @suggestions}
                suggestion={suggestion}
                contact={@selected_contact}
                field_options={@field_options}
                myself={@myself}
                meeting_path={@meeting_path}
              />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text={@provider_config.submit_text}
              submit_class={@provider_config.submit_class}
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={@info_text}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    provider =
      assigns
      |> Map.get(:provider, socket.assigns[:provider] || CrmProviders.default_provider_id())
      |> CrmProviders.normalize_provider()

    provider_config = CrmProviders.get(provider)
    reauth_required = reauth_required_for(provider, assigns, socket)

    socket =
      socket
      |> assign(assigns)
      |> assign(:provider, provider)
      |> assign(:provider_config, provider_config)
      |> assign(:reauth_required, reauth_required)
      |> ensure_apply_defaults(assigns)
      |> assign_new(:step, fn -> :search end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:contacts, fn -> [] end)
      |> assign_new(:selected_contact, fn -> nil end)
      |> assign_new(:suggestions, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:dropdown_open, fn -> false end)
      |> assign_new(:error, fn -> nil end)

    {:ok, socket}
  end

  defp ensure_apply_defaults(socket, %{suggestions: suggestions}) when is_list(suggestions) do
    contact = socket.assigns[:selected_contact]
    contact_country = contact_country(contact)

    updated =
      Enum.map(suggestions, fn suggestion ->
        suggestion = Map.put_new(suggestion, :apply, false)

        if suggestion.field == "MailingState" and is_binary(contact_country) and contact_country != "" do
          Map.put_new(suggestion, :country_value, contact_country)
        else
          suggestion
        end
      end)

    assign(socket, suggestions: updated)
  end

  defp ensure_apply_defaults(socket, _assigns), do: socket

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)
    provider_config = socket.assigns.provider_config

    cond do
      provider_config.reauth && socket.assigns.reauth_required ->
        {:noreply,
         assign(socket,
           searching: false,
           dropdown_open: false,
           error: "Reconnect #{provider_config.name} to search contacts.",
           query: query
         )}

      String.length(query) >= 2 ->
        socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
        send(self(), {:crm_search, socket.assigns.provider, query, socket.assigns.credential})
        {:noreply, socket}

      true ->
        {:noreply, assign(socket, query: query, contacts: [], dropdown_open: query != "")}
    end
  end

  @impl true
  def handle_event("open_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: true)}
  end

  @impl true
  def handle_event("close_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  @impl true
  def handle_event("toggle_contact_dropdown", _params, socket) do
    provider_config = socket.assigns.provider_config

    cond do
      provider_config.reauth && socket.assigns.reauth_required ->
        {:noreply, assign(socket, error: "Reconnect #{provider_config.name} to search contacts.")}

      socket.assigns.dropdown_open ->
        {:noreply, assign(socket, dropdown_open: false)}

      true ->
        socket = assign(socket, dropdown_open: true, searching: true)
        query = "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"
        send(self(), {:crm_search, socket.assigns.provider, query, socket.assigns.credential})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    provider_config = socket.assigns.provider_config

    if provider_config.reauth && socket.assigns.reauth_required do
      {:noreply, assign(socket, error: "Reconnect #{provider_config.name} to load contacts.")}
    else
      contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

      if contact do
        socket =
          assign(socket,
            loading: true,
            selected_contact: contact,
            error: nil,
            dropdown_open: false,
            query: "",
            suggestions: []
          )

        send(
          self(),
          {:crm_generate_suggestions, socket.assigns.provider, contact, socket.assigns.meeting,
           socket.assigns.credential}
        )
        {:noreply, socket}
      else
        {:noreply, assign(socket, error: "Contact not found")}
      end
    end
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply,
     assign(socket,
       step: :search,
       selected_contact: nil,
       suggestions: [],
       loading: false,
       searching: false,
       dropdown_open: false,
       contacts: [],
       query: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("toggle_suggestion", params, socket) do
    applied_fields = Map.get(params, "apply", %{})
    values = Map.get(params, "values", %{})
    mapping = Map.get(params, "mapping", %{})
    checked_fields = remap_apply_fields(applied_fields, mapping)
    mapped_values = remap_values(values, mapping)
    provider_config = socket.assigns.provider_config

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        old_field = suggestion.field
        new_field = Map.get(mapping, old_field, old_field)
        mapping_changed = old_field != new_field
        apply? = new_field in checked_fields
        new_value = Map.get(mapped_values, new_field, suggestion.new_value)
        country_value = Map.get(values, "MailingCountry")

        suggestion =
          if mapping_changed do
            %{
              suggestion
              | field: new_field,
                label: provider_config.suggestions_module.field_label(new_field),
                current_value: contact_field_value(socket.assigns.selected_contact, new_field),
              mapping_open: false
            }
          else
            suggestion
          end

        suggestion =
          if new_field == "MailingState" and is_binary(country_value) do
            Map.put(suggestion, :country_value, country_value)
          else
            suggestion
          end

        %{suggestion | apply: apply?, new_value: new_value}
      end)

    {:noreply, assign(socket, suggestions: updated_suggestions)}
  end

  @impl true
  def handle_event("toggle_mapping", %{"field" => field}, socket) do
    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        if suggestion.field == field do
          mapping_open = !Map.get(suggestion, :mapping_open, false)
          %{suggestion | apply: true, mapping_open: mapping_open}
        else
          Map.put(suggestion, :mapping_open, false)
        end
      end)

    {:noreply, assign(socket, suggestions: updated_suggestions)}
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
    provider_config = socket.assigns.provider_config

    if provider_config.reauth && socket.assigns.reauth_required do
      {:noreply, assign(socket, error: "Reconnect #{provider_config.name} to apply updates.")}
    else
      socket = assign(socket, loading: true, error: nil)

      updates =
        selected
        |> Map.keys()
        |> Enum.reduce(%{}, fn field, acc ->
          Map.put(acc, field, Map.get(values, field, ""))
        end)
        |> maybe_add_salesforce_country(values, socket.assigns.provider)

      send(
        self(),
        {:crm_apply_updates, socket.assigns.provider, updates, socket.assigns.selected_contact,
         socket.assigns.credential}
      )
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end

  defp remap_apply_fields(applied_fields, mapping) do
    applied_fields
    |> Map.keys()
    |> Enum.map(fn field -> Map.get(mapping, field, field) end)
  end

  defp remap_values(values, mapping) do
    Enum.reduce(values, %{}, fn {field, value}, acc ->
      Map.put(acc, Map.get(mapping, field, field), value)
    end)
  end

  defp maybe_add_salesforce_country(updates, values, provider) when is_map(updates) and is_map(values) do
    if CrmProviders.normalize_provider(provider) == "salesforce" and Map.has_key?(updates, "MailingState") do
      country_value = Map.get(values, "MailingCountry", "")

      if is_binary(country_value) and String.trim(country_value) != "" do
        Map.put_new(updates, "MailingCountry", country_value)
      else
        updates
      end
    else
      updates
    end
  end

  defp maybe_add_salesforce_country(updates, _values, _provider), do: updates

  defp contact_field_value(contact, field) when is_map(contact) and is_binary(field) do
    Map.get(contact, field) ||
      (try do
         Map.get(contact, String.to_existing_atom(field))
       rescue
         ArgumentError -> nil
       end)
  end

  defp contact_field_value(_, _), do: nil

  defp contact_country(contact) when is_map(contact) do
    Map.get(contact, "MailingCountry") ||
      Map.get(contact, :mailing_country) ||
      Map.get(contact, "country") ||
      Map.get(contact, :country)
  end

  defp contact_country(_), do: nil

  defp reauth_required_for(provider, assigns, socket) do
    case Map.fetch(assigns, :reauth_required) do
      {:ok, value} ->
        value

      :error ->
        credential = Map.get(assigns, :credential, socket.assigns[:credential])
        CrmProviders.reauth_required?(provider, credential)
    end
  end
end
