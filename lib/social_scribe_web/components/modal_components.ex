defmodule SocialScribeWeb.ModalComponents do
  @moduledoc """
  Reusable UI components for modals and dialogs.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import SocialScribeWeb.CoreComponents, only: [icon: 1]

  @state_fields ["MailingState", "state"]
  @state_option_pairs [
    {"Alabama", "AL"},
    {"Alaska", "AK"},
    {"Arizona", "AZ"},
    {"Arkansas", "AR"},
    {"California", "CA"},
    {"Colorado", "CO"},
    {"Connecticut", "CT"},
    {"Delaware", "DE"},
    {"District of Columbia", "DC"},
    {"Florida", "FL"},
    {"Georgia", "GA"},
    {"Hawaii", "HI"},
    {"Idaho", "ID"},
    {"Illinois", "IL"},
    {"Indiana", "IN"},
    {"Iowa", "IA"},
    {"Kansas", "KS"},
    {"Kentucky", "KY"},
    {"Louisiana", "LA"},
    {"Maine", "ME"},
    {"Maryland", "MD"},
    {"Massachusetts", "MA"},
    {"Michigan", "MI"},
    {"Minnesota", "MN"},
    {"Mississippi", "MS"},
    {"Missouri", "MO"},
    {"Montana", "MT"},
    {"Nebraska", "NE"},
    {"Nevada", "NV"},
    {"New Hampshire", "NH"},
    {"New Jersey", "NJ"},
    {"New Mexico", "NM"},
    {"New York", "NY"},
    {"North Carolina", "NC"},
    {"North Dakota", "ND"},
    {"Ohio", "OH"},
    {"Oklahoma", "OK"},
    {"Oregon", "OR"},
    {"Pennsylvania", "PA"},
    {"Rhode Island", "RI"},
    {"South Carolina", "SC"},
    {"South Dakota", "SD"},
    {"Tennessee", "TN"},
    {"Texas", "TX"},
    {"Utah", "UT"},
    {"Vermont", "VT"},
    {"Virginia", "VA"},
    {"Washington", "WA"},
    {"West Virginia", "WV"},
    {"Wisconsin", "WI"},
    {"Wyoming", "WY"},
    {"Alberta", "AB"},
    {"British Columbia", "BC"},
    {"Manitoba", "MB"},
    {"New Brunswick", "NB"},
    {"Newfoundland and Labrador", "NL"},
    {"Northwest Territories", "NT"},
    {"Nova Scotia", "NS"},
    {"Nunavut", "NU"},
    {"Ontario", "ON"},
    {"Prince Edward Island", "PE"},
    {"Quebec", "QC"},
    {"Saskatchewan", "SK"},
    {"Yukon", "YT"}
  ]
  @state_name_options Enum.map(@state_option_pairs, fn {name, _code} -> {name, name} end)
  @state_code_options @state_option_pairs
  @state_name_map Map.new(@state_option_pairs, fn {name, _code} -> {String.downcase(name), name} end)
  @state_name_to_code Map.new(@state_option_pairs, fn {name, code} -> {String.downcase(name), code} end)
  @state_code_to_name Map.new(@state_option_pairs, fn {name, code} -> {String.downcase(code), name} end)
  @country_options [
    {"United States", "United States"},
    {"Canada", "Canada"}
  ]

  @doc """
  Renders a searchable contact select box.

  Shows selected contact with avatar, or search input when no contact selected.
  Auto-searches when typing, dropdown shows results.

  ## Examples

      <.contact_select
        selected_contact={@selected_contact}
        contacts={@contacts}
        loading={@loading}
        open={@dropdown_open}
        query={@query}
        target={@myself}
      />
  """
  attr :selected_contact, :map, default: nil
  attr :contacts, :list, default: []
  attr :loading, :boolean, default: false
  attr :open, :boolean, default: false
  attr :query, :string, default: ""
  attr :target, :any, default: nil
  attr :error, :string, default: nil
  attr :id, :string, default: "contact-select"

  def contact_select(assigns) do
    ~H"""
    <div id={@id} phx-hook="ContactSelect" class="space-y-1">
      <label for={"#{@id}-input"} class="block text-sm font-medium text-slate-700">Select Contact</label>
      <div class="relative">
        <%= if @selected_contact do %>
          <button
            type="button"
            phx-click="toggle_contact_dropdown"
            phx-target={@target}
            role="combobox"
            aria-haspopup="listbox"
            aria-expanded={to_string(@open)}
            aria-controls={"#{@id}-listbox"}
            class="relative w-full bg-white border border-hubspot-input rounded-lg pl-1.5 pr-10 py-[5px] text-left cursor-pointer focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"
          >
            <span class="flex items-center">
              <.avatar firstname={@selected_contact.firstname} lastname={@selected_contact.lastname} size={:sm} />
              <span class="ml-1.5 block truncate text-slate-900">
                {@selected_contact.firstname} {@selected_contact.lastname}
              </span>
            </span>
            <span class="absolute inset-y-0 right-0 flex items-center pr-2 pointer-events-none">
              <.icon name="hero-chevron-up-down" class="h-5 w-5 text-hubspot-icon" />
            </span>
          </button>
        <% else %>
          <div class="relative">
            <input
              id={"#{@id}-input"}
              type="text"
              name="contact_query"
              value={@query}
              placeholder="Search contacts..."
              phx-keyup="contact_search"
              phx-target={@target}
              phx-focus="open_contact_dropdown"
              phx-debounce="150"
              autocomplete="off"
              role="combobox"
              aria-autocomplete="list"
              aria-expanded={to_string(@open)}
              aria-controls={"#{@id}-listbox"}
              class="w-full bg-white border border-hubspot-input rounded-lg pl-2 pr-10 py-[5px] text-left focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"
            />
            <span class="absolute inset-y-0 right-0 flex items-center pr-2 pointer-events-none">
              <%= if @loading do %>
                <.icon name="hero-arrow-path" class="h-5 w-5 text-hubspot-icon animate-spin" />
              <% else %>
                <.icon name="hero-chevron-up-down" class="h-5 w-5 text-hubspot-icon" />
              <% end %>
            </span>
          </div>
        <% end %>

        <div
          :if={@open && (@selected_contact || Enum.any?(@contacts) || @loading || @query != "")}
          id={"#{@id}-listbox"}
          role="listbox"
          data-contact-select-listbox
          phx-click-away="close_contact_dropdown"
          phx-target={@target}
          class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm"
        >
          <button
            :if={@selected_contact}
            type="button"
            phx-click="clear_contact"
            phx-target={@target}
            role="option"
            aria-selected={"false"}
            data-contact-select-item
            class="w-full text-left px-4 py-2 hover:bg-slate-50 text-sm text-slate-700 cursor-pointer"
          >
            Clear selection
          </button>
          <div :if={@loading} class="px-4 py-2 text-sm text-gray-500">
            Searching...
          </div>
          <div :if={!@loading && Enum.empty?(@contacts) && @query != ""} class="px-4 py-2 text-sm text-gray-500">
            No contacts found
          </div>
          <button
            :for={contact <- @contacts}
            type="button"
            phx-click="select_contact"
            phx-value-id={contact.id}
            phx-target={@target}
            role="option"
            aria-selected={"false"}
            data-contact-select-item
            class="w-full text-left px-4 py-2 hover:bg-slate-50 flex items-center space-x-3 cursor-pointer"
          >
            <.avatar firstname={contact.firstname} lastname={contact.lastname} size={:sm} />
            <div>
              <div class="text-sm font-medium text-slate-900">
                {contact.firstname} {contact.lastname}
              </div>
              <div class="text-xs text-slate-500">
                {contact.email}
              </div>
            </div>
          </button>
        </div>
      </div>
      <.inline_error :if={@error} message={@error} />
    </div>
    """
  end

  @doc """
  Renders a search input with icon.

  ## Examples

      <.search_input
        name="query"
        value=""
        placeholder="Search..."
        loading={false}
      />
  """
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: "Search..."
  attr :loading, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def search_input(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
        <.icon name="hero-magnifying-glass" class="h-5 w-5 text-gray-400" />
      </div>
      <input
        type="text"
        name={@name}
        value={@value}
        class="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
        placeholder={@placeholder}
        {@rest}
      />
      <div :if={@loading} class="absolute inset-y-0 right-0 pr-3 flex items-center">
        <.icon name="hero-arrow-path" class="h-4 w-4 text-gray-400 animate-spin" />
      </div>
    </div>
    """
  end

  @doc """
  Renders an avatar with initials.

  ## Examples

      <.avatar firstname="John" lastname="Doe" size={:md} />
  """
  attr :firstname, :string, default: ""
  attr :lastname, :string, default: ""
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :class, :string, default: nil

  def avatar(assigns) do
    size_classes = %{
      sm: "h-6 w-6 text-[10px]",
      md: "h-8 w-8 text-[10px]",
      lg: "h-10 w-10 text-sm"
    }

    assigns = assign(assigns, :size_class, size_classes[assigns.size])

    ~H"""
    <div class={[
      "rounded-full bg-hubspot-avatar flex items-center justify-center font-semibold text-hubspot-avatar-text flex-shrink-0",
      @size_class,
      @class
    ]}>
      {String.at(@firstname || "", 0)}{String.at(@lastname || "", 0)}
    </div>
    """
  end

  @doc """
  Renders a clickable contact list item.

  ## Examples

      <.contact_list_item
        contact={%{firstname: "John", lastname: "Doe", email: "john@example.com"}}
        on_click="select_contact"
        target={@myself}
      />
  """
  attr :contact, :map, required: true
  attr :on_click, :string, required: true
  attr :target, :any, default: nil
  attr :class, :string, default: nil

  def contact_list_item(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@on_click}
      phx-value-id={@contact.id}
      phx-target={@target}
      class={[
        "w-full px-4 py-3 text-left hover:bg-slate-50 transition-colors flex items-center space-x-3",
        @class
      ]}
    >
      <.avatar firstname={@contact.firstname} lastname={@contact.lastname} size={:md} />
      <div>
        <div class="text-sm font-medium text-slate-900">
          {@contact.firstname} {@contact.lastname}
        </div>
        <div class="text-xs text-slate-500">
          {@contact.email}
          <span :if={@contact[:company]} class="text-slate-400">· {@contact.company}</span>
        </div>
      </div>
    </button>
    """
  end

  @doc """
  Renders a contact list container.

  ## Examples

      <.contact_list>
        <.contact_list_item :for={c <- @contacts} contact={c} on_click="select" />
      </.contact_list>
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def contact_list(assigns) do
    ~H"""
    <div class={[
      "border border-gray-200 rounded-md divide-y divide-gray-200 max-h-64 overflow-y-auto bg-white shadow-sm",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a value comparison (old → new).

  ## Examples

      <.value_comparison
        current_value="old@email.com"
        new_value="new@email.com"
      />
  """
  attr :current_value, :string, default: nil
  attr :new_value, :string, required: true
  attr :class, :string, default: nil

  def value_comparison(assigns) do
    ~H"""
    <div class={["flex items-center gap-6", @class]}>
      <div class="flex-1">
        <input
          type="text"
          readonly
          value={@current_value || ""}
          placeholder="No existing value"
          class={[
            "block w-full shadow-sm text-sm bg-white border border-hubspot-input rounded-[7px] py-1.5 px-2",
            if(@current_value && @current_value != "", do: "line-through text-slate-500", else: "text-slate-400")
          ]}
        />
      </div>
      <div class="text-slate-300">
        <.icon name="hero-arrow-long-right" class="h-6 w-6" />
      </div>
      <div class="flex-1">
        <input
          type="text"
          readonly
          value={@new_value}
          class="block w-full shadow-sm text-sm text-slate-900 bg-white border border-hubspot-input rounded-[7px] py-1.5 px-2 focus:ring-blue-500 focus:border-blue-500"
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a suggestion card with checkbox.

  ## Examples

      <.suggestion_card suggestion={%{field: "email", label: "Email", ...}} />
  """
  attr :suggestion, :map, required: true
  attr :contact, :map, default: nil
  attr :myself, :any, default: nil
  attr :field_options, :list, default: []
  attr :meeting_path, :string, default: nil
  attr :class, :string, default: nil

  def suggestion_card(assigns) do
    ~H"""
    <div class={["bg-hubspot-card rounded-2xl p-6 mb-4", @class]}>
      <div class="flex items-start justify-between">
        <div class="flex items-start gap-3">
          <div class="flex items-center h-5 pt-0.5">
            <input
              id={"suggestion-apply-#{@suggestion.field}"}
              type="checkbox"
              name={"apply[#{@suggestion.field}]"}
              value="1"
              checked={@suggestion.apply}
              class="h-4 w-4 rounded-[3px] border-slate-300 text-hubspot-checkbox accent-hubspot-checkbox focus:ring-0 focus:ring-offset-0 cursor-pointer"
            />
          </div>
          <div class="text-sm font-semibold text-slate-900 leading-5">
            <%= if @suggestion[:mapping_open] && @field_options != [] do %>
              <select
                id={"suggestion-mapping-#{@suggestion.field}"}
                name={"mapping[#{@suggestion.field}]"}
                class="text-sm font-semibold bg-white border border-slate-300 rounded-md px-2 py-1 text-slate-900"
                aria-label="Select field to update"
              >
                <option :for={{label, value} <- @field_options} value={value} selected={value == @suggestion.field}>
                  {label}
                </option>
              </select>
            <% else %>
              {@suggestion.label}
            <% end %>
          </div>
        </div>

        <div class="flex items-center gap-3 pt-0.5">
          <span
            class={[
              "inline-flex items-center rounded-full bg-hubspot-pill px-2 py-1 text-xs font-medium text-hubspot-pill-text",
              if(@suggestion.apply, do: "opacity-100", else: "opacity-0 pointer-events-none")
            ]}
            aria-hidden={to_string(!@suggestion.apply)}
          >
            1 update selected
          </span>
          <button type="button" class="text-xs text-hubspot-hide hover:text-hubspot-hide-hover font-medium">
            Hide details
          </button>
        </div>
      </div>

      <div class="mt-2 pl-8">
        <div
          :if={@suggestion[:person] && @suggestion[:person] != ""}
          class="mt-1 text-xs text-slate-500 ml-1"
        >
          Suggested person:
          <span class="font-medium text-slate-700">{@suggestion[:person]}</span>
        </div>

        <div class="mt-2">
          <div class="grid grid-cols-[1fr_32px_1fr] items-center gap-6">
            <input
              type="text"
              readonly
              value={@suggestion.current_value || ""}
              placeholder="No existing value"
              class={[
                "block w-full shadow-sm text-sm bg-white border border-gray-300 rounded-[7px] py-1.5 px-2",
                if(@suggestion.current_value && @suggestion.current_value != "", do: "line-through text-gray-500", else: "text-gray-400")
              ]}
            />

            <div class="w-8 flex justify-center text-hubspot-arrow">
              <.icon name="hero-arrow-long-right" class="h-7 w-7" />
            </div>

            <%= if state_field?(@suggestion.field) do %>
              <select
                name={"values[#{@suggestion.field}]"}
                id={"suggestion-value-#{@suggestion.field}"}
                class="block w-full shadow-sm text-sm text-slate-900 bg-white border border-hubspot-input rounded-[7px] py-1.5 px-2 focus:ring-blue-500 focus:border-blue-500"
              >
                <option value="" selected={state_selected_value(@suggestion.field, @suggestion.new_value) == ""}>
                  Select a state/province
                </option>
                <option
                  :for={{label, value} <- state_select_options(@suggestion.field, @suggestion.new_value)}
                  value={value}
                  selected={value == state_selected_value(@suggestion.field, @suggestion.new_value)}
                >
                  {label}
                </option>
              </select>
            <% else %>
              <input
                type="text"
                name={"values[#{@suggestion.field}]"}
                id={"suggestion-value-#{@suggestion.field}"}
                value={@suggestion.new_value}
                class="block w-full shadow-sm text-sm text-slate-900 bg-white border border-hubspot-input rounded-[7px] py-1.5 px-2 focus:ring-blue-500 focus:border-blue-500"
              />
            <% end %>
          </div>
        </div>

        <%= if @suggestion.field == "MailingState" do %>
          <% country_value = suggestion_country_value(@suggestion, @contact) %>
          <div class="mt-3">
            <div class="grid grid-cols-[1fr_32px_1fr] items-center gap-6">
              <input
                type="text"
                readonly
                value={contact_country(@contact) || ""}
                placeholder="No existing value"
                class={[
                  "block w-full shadow-sm text-sm bg-white border border-gray-300 rounded-[7px] py-1.5 px-2",
                  if(contact_country(@contact) && contact_country(@contact) != "",
                    do: "line-through text-gray-500",
                    else: "text-gray-400"
                  )
                ]}
              />

              <div class="w-8 flex justify-center text-hubspot-arrow">
                <.icon name="hero-arrow-long-right" class="h-7 w-7" />
              </div>

              <select
                name="values[MailingCountry]"
                id="suggestion-country-MailingState"
                class="block w-full shadow-sm text-sm text-slate-900 bg-white border border-hubspot-input rounded-[7px] py-1.5 px-2 focus:ring-blue-500 focus:border-blue-500"
              >
                <option value="" selected={country_selected_value(country_value) == ""}>
                  Select a country/territory
                </option>
                <option
                  :for={{label, value} <- country_select_options(country_value)}
                  value={value}
                  selected={value == country_selected_value(country_value)}
                >
                  {label}
                </option>
              </select>
            </div>
          </div>
        <% end %>

        <div class="mt-3 grid grid-cols-[1fr_32px_1fr] items-start gap-6">
          <button
            type="button"
            phx-click={JS.push("toggle_mapping", value: %{field: @suggestion.field}, target: @myself)}
            class="text-xs text-hubspot-link hover:text-hubspot-link-hover font-medium justify-self-start"
          >
            <%= if @suggestion[:mapping_open] do %>
              Close mapping
            <% else %>
              Update mapping
            <% end %>
          </button>
          <span></span>
          <span :if={@suggestion[:timestamp]} class="text-xs text-slate-500 justify-self-start">
            Found in transcript
            <%= if @meeting_path do %>
              <a
                href={"#{@meeting_path}?t=#{URI.encode_www_form(@suggestion[:timestamp])}#meeting-transcript"}
                target="_blank"
                rel="noopener noreferrer"
                class="text-hubspot-link hover:underline"
                title={@suggestion[:context]}
                aria-label={"Open transcript at #{@suggestion[:timestamp]} in a new tab"}
              >
                ({@suggestion[:timestamp]})
              </a>
            <% else %>
              <span class="text-hubspot-link cursor-help" title={@suggestion[:context]}>
                ({@suggestion[:timestamp]})
              </span>
            <% end %>
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp state_field?(field) when is_atom(field), do: state_field?(Atom.to_string(field))
  defp state_field?(field) when is_binary(field), do: field in @state_fields
  defp state_field?(_field), do: false

  defp state_select_options(field, selected_value) do
    {options, selected_value} = state_options_for_field(field, selected_value)

    if selected_value != "" and Enum.all?(options, fn {_label, value} -> value != selected_value end) do
      [{selected_value, selected_value} | options]
    else
      options
    end
  end

  defp state_options_for_field(field, selected_value) when is_binary(field) do
    case field do
      "MailingState" -> {@state_code_options, state_selected_value(:code, selected_value)}
      "state" -> {@state_name_options, state_selected_value(:name, selected_value)}
      _ -> {@state_name_options, state_selected_value(:name, selected_value)}
    end
  end

  defp state_options_for_field(_field, selected_value),
    do: {@state_name_options, state_selected_value(:name, selected_value)}

  defp state_selected_value(mode, value) when is_binary(value) do
    trimmed = String.trim(value)

    case mode do
      :code -> state_code_from_value(trimmed) || trimmed
      :name -> state_name_from_value(trimmed) || trimmed
      _ -> trimmed
    end
  end

  defp state_selected_value(_mode, _value), do: ""

  defp state_code_from_value(""), do: nil

  defp state_code_from_value(value) when is_binary(value) do
    normalized = String.downcase(value)

    cond do
      Map.has_key?(@state_code_to_name, normalized) -> String.upcase(value)
      true -> Map.get(@state_name_to_code, normalized)
    end
  end

  defp state_code_from_value(_value), do: nil

  defp state_name_from_value(""), do: nil

  defp state_name_from_value(value) when is_binary(value) do
    normalized = String.downcase(value)
    Map.get(@state_code_to_name, normalized) || Map.get(@state_name_map, normalized)
  end

  defp state_name_from_value(_value), do: nil

  defp country_select_options(selected_value) do
    selected_value = country_selected_value(selected_value)

    if selected_value != "" and Enum.all?(@country_options, fn {_label, value} -> value != selected_value end) do
      [{selected_value, selected_value} | @country_options]
    else
      @country_options
    end
  end

  defp country_selected_value(value) when is_binary(value), do: String.trim(value)
  defp country_selected_value(_value), do: ""

  defp contact_country(contact) when is_map(contact) do
    Map.get(contact, "MailingCountry") ||
      Map.get(contact, :mailing_country) ||
      Map.get(contact, "country") ||
      Map.get(contact, :country)
  end

  defp contact_country(_), do: nil

  defp suggestion_country_value(suggestion, contact) do
    Map.get(suggestion, :country_value) ||
      Map.get(suggestion, "country_value") ||
      contact_country(contact) ||
      ""
  end

  @doc """
  Renders a success message with checkmark icon.

  ## Examples

      <.success_message title="Success!" message="Operation completed." />
  """
  attr :title, :string, required: true
  attr :message, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block
  slot :actions

  def success_message(assigns) do
    ~H"""
    <div class={["text-center py-8", @class]}>
      <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-green-100 mb-4">
        <.icon name="hero-check" class="h-6 w-6 text-green-600" />
      </div>
      <h3 class="text-lg font-medium text-slate-800 mb-2">{@title}</h3>
      <p :if={@message} class="text-slate-500 mb-6">{@message}</p>
      <div :if={@inner_block != []} class="text-slate-500 mb-6">
        {render_slot(@inner_block)}
      </div>
      <div :if={@actions != []}>
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a modal footer with cancel and submit buttons.

  ## Examples

      <.modal_footer
        cancel_url={~p"/dashboard"}
        submit_text="Save"
        loading={false}
      />
  """
  attr :cancel_patch, :string, default: nil
  attr :cancel_click, :any, default: nil
  attr :submit_text, :string, default: "Submit"
  attr :submit_class, :string, default: "bg-green-600 hover:bg-green-700"
  attr :loading, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :loading_text, :string, default: "Processing..."
  attr :info_text, :string, default: nil
  attr :class, :string, default: nil

  def modal_footer(assigns) do
    ~H"""
    <div class={["relative pt-6 mt-6 flex items-center justify-between -mx-10 px-10", @class]}>
      <div class="absolute left-0 right-0 top-0 border-t border-slate-200"></div>
      <div :if={@info_text} class="text-xs text-slate-500">
        {@info_text}
      </div>
      <div :if={!@info_text}></div>
      <div class="flex space-x-3">
        <button
          :if={@cancel_patch}
          type="button"
          phx-click={Phoenix.LiveView.JS.patch(@cancel_patch)}
          class="px-5 py-2.5 border border-slate-300 rounded-lg shadow-sm text-sm font-medium text-hubspot-cancel bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          Cancel
        </button>
        <button
          :if={@cancel_click}
          type="button"
          phx-click={@cancel_click}
          class="px-5 py-2.5 border border-slate-300 rounded-lg shadow-sm text-sm font-medium text-hubspot-cancel bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={@loading || @disabled}
          class={
            "px-5 py-2.5 rounded-lg shadow-sm text-sm font-medium text-white " <>
              @submit_class <> " disabled:opacity-50"
          }
        >
          <span :if={@loading}>{@loading_text}</span>
          <span :if={!@loading}>{@submit_text}</span>
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty state message.

  ## Examples

      <.empty_state title="No results" message="Try a different search." />
  """
  attr :title, :string, default: nil
  attr :message, :string, required: true
  attr :submessage, :string, default: nil
  attr :class, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class={["text-center py-8 text-slate-500", @class]}>
      <p :if={@title} class="font-medium text-slate-700 mb-1">{@title}</p>
      <p>{@message}</p>
      <p :if={@submessage} class="text-sm mt-2">{@submessage}</p>
    </div>
    """
  end

  @doc """
  Renders an error message.

  ## Examples

      <.inline_error :if={@error} message={@error} />
  """
  attr :message, :string, required: true
  attr :class, :string, default: nil

  def inline_error(assigns) do
    ~H"""
    <p class={["text-red-600 text-sm", @class]}>{@message}</p>
    """
  end

  @doc """
  Renders a CRM provider icon.

  ## Examples

      <.crm_provider_icon provider={%{icon: :hubspot}} />
  """
  attr :provider, :map, required: true
  attr :class, :string, default: "w-5 h-5 mr-2"

  def crm_provider_icon(assigns) do
    ~H"""
    <%= case @provider.icon do %>
      <% :hubspot -> %>
        <svg class={@class} fill="currentColor" viewBox="0 0 24 24">
          <path d="M18.72 14.76c.35-.85.54-1.76.54-2.76 0-.72-.11-1.41-.3-2.05-.65.15-1.33.23-2.04.23A9.07 9.07 0 0112 9.9a8.963 8.963 0 01-4.92.28c-.2.64-.3 1.33-.3 2.05 0 1 .19 1.91.54 2.76 1.34-.5 2.75-.79 4.18-.79s2.84.29 4.22.79M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2m0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8m0-14c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3" />
        </svg>
      <% :salesforce -> %>
        <.icon name="hero-cloud" class={@class} />
      <% _ -> %>
        <.icon name="hero-cloud" class={@class} />
    <% end %>
    """
  end

  @doc """
  Renders a HubSpot-styled modal wrapper.

  This is a specialized modal with HubSpot-specific styling:
  - Custom overlay color
  - Reduced padding
  - No close button (relies on Cancel button in footer)

  ## Examples

      <.hubspot_modal id="hubspot-modal" show on_cancel={JS.patch(~p"/back")}>
        Modal content here
      </.hubspot_modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def hubspot_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-hubspot-overlay/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white px-10 py-7 shadow-lg ring-1 transition"
            >
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  defp hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      time: 200,
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      time: 200,
      transition:
        {"transition-all ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end
end
