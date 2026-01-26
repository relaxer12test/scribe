defmodule SocialScribeWeb.MeetingLive.HubspotModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents
  alias SocialScribe.HubspotSuggestions

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "hubspot-modal-wrapper" end)

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">Update in HubSpot</h2>
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
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true

  defp suggestions_section(assigns) do
    assigns =
      assigns
      |> assign(:selected_count, Enum.count(assigns.suggestions, & &1.apply))
      |> assign(:field_options, HubspotSuggestions.field_options())

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
                field_options={@field_options}
                myself={@myself}
              />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text="Update HubSpot"
              submit_class="bg-hubspot-button hover:bg-hubspot-button-hover"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={"1 object, #{@selected_count} fields in 1 integration selected to update"}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_select_all_suggestions(assigns)
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

  defp maybe_select_all_suggestions(socket, %{suggestions: suggestions}) when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  defp maybe_select_all_suggestions(socket, _assigns), do: socket

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
      send(self(), {:hubspot_search, query, socket.assigns.credential})
      {:noreply, socket}
    else
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
    if socket.assigns.dropdown_open do
      {:noreply, assign(socket, dropdown_open: false)}
    else
      # When opening dropdown with selected contact, search for similar contacts
      socket = assign(socket, dropdown_open: true, searching: true)
      query = "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"
      send(self(), {:hubspot_search, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

    if contact do
      socket = assign(socket,
        loading: true,
        selected_contact: contact,
        error: nil,
        dropdown_open: false,
        query: "",
        suggestions: []
      )
      send(self(), {:generate_suggestions, contact, socket.assigns.meeting, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Contact not found")}
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

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        old_field = suggestion.field
        new_field = Map.get(mapping, old_field, old_field)
        mapping_changed = old_field != new_field
        apply? = new_field in checked_fields
        new_value = Map.get(mapped_values, new_field, suggestion.new_value)

        suggestion =
          if mapping_changed do
            %{
              suggestion
              | field: new_field,
                label: HubspotSuggestions.field_label(new_field),
                current_value: contact_field_value(socket.assigns.selected_contact, new_field),
                mapping_open: false
            }
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
    socket = assign(socket, loading: true, error: nil)

    updates =
      selected
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        Map.put(acc, field, Map.get(values, field, ""))
      end)

    send(self(), {:apply_hubspot_updates, updates, socket.assigns.selected_contact, socket.assigns.credential})
    {:noreply, socket}
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

  defp contact_field_value(contact, field) when is_map(contact) and is_binary(field) do
    Map.get(contact, field) ||
      (try do
         Map.get(contact, String.to_existing_atom(field))
       rescue
         ArgumentError -> nil
       end)
  end

  defp contact_field_value(_, _), do: nil
end
