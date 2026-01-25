defmodule SocialScribeWeb.MeetingLive.SalesforceModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "salesforce-modal-wrapper" end)

    ~H"""
    <div class="space-y-6">
      <%= if @reauth_required do %>
        <div class="rounded-lg border border-amber-200 bg-amber-50 p-4 text-amber-900 shadow-sm">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p class="font-semibold">Reconnect Salesforce to continue</p>
              <p class="text-sm text-amber-800">
                We couldn't refresh your Salesforce connection. Reconnect to keep updates working.
              </p>
            </div>
            <.link
              href={~p"/auth/salesforce?prompt=consent"}
              method="get"
              class="inline-flex items-center justify-center rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-amber-700"
            >
              Reconnect Salesforce
            </.link>
          </div>
        </div>
      <% end %>
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">
          Update in Salesforce
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
    assigns = assign(assigns, :selected_count, Enum.count(assigns.suggestions, & &1.apply))

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
              <.suggestion_card :for={suggestion <- @suggestions} suggestion={suggestion} />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text="Update Salesforce"
              submit_class="bg-sky-600 hover:bg-sky-700"
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
    reauth_required =
      case Map.fetch(assigns, :reauth_required) do
        {:ok, value} ->
          value

        :error ->
          case assigns[:credential] do
            %{reauth_required_at: %DateTime{}} -> true
            _ -> false
          end
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:reauth_required, reauth_required)
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

    cond do
      socket.assigns.reauth_required ->
        {:noreply,
         assign(socket,
           searching: false,
           dropdown_open: false,
           error: "Reconnect Salesforce to search contacts.",
           query: query
         )}

      String.length(query) >= 2 ->
        socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
        send(self(), {:salesforce_search, query, socket.assigns.credential})
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
    cond do
      socket.assigns.reauth_required ->
        {:noreply, assign(socket, error: "Reconnect Salesforce to search contacts.")}

      socket.assigns.dropdown_open ->
        {:noreply, assign(socket, dropdown_open: false)}

      true ->
        socket = assign(socket, dropdown_open: true, searching: true)
        query = "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"
        send(self(), {:salesforce_search, query, socket.assigns.credential})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    if socket.assigns.reauth_required do
      {:noreply, assign(socket, error: "Reconnect Salesforce to load contacts.")}
    else
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

        send(self(), {:generate_salesforce_suggestions, contact, socket.assigns.meeting, socket.assigns.credential})
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
    checked_fields = Map.keys(applied_fields)

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        apply? = suggestion.field in checked_fields

        suggestion =
          case Map.get(values, suggestion.field) do
            nil -> suggestion
            new_value -> %{suggestion | new_value: new_value}
          end

        %{suggestion | apply: apply?}
      end)

    {:noreply, assign(socket, suggestions: updated_suggestions)}
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
    if socket.assigns.reauth_required do
      {:noreply, assign(socket, error: "Reconnect Salesforce to apply updates.")}
    else
      socket = assign(socket, loading: true, error: nil)

      updates =
        selected
        |> Map.keys()
        |> Enum.reduce(%{}, fn field, acc ->
          Map.put(acc, field, Map.get(values, field, ""))
        end)

      send(self(), {:apply_salesforce_updates, updates, socket.assigns.selected_contact, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end
end
