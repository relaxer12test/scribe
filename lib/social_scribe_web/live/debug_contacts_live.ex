defmodule SocialScribeWeb.DebugContactsLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApi
  alias SocialScribe.SalesforceApi

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    hubspot_credential = Accounts.get_user_hubspot_credential(user.id)
    salesforce_credential = Accounts.get_user_credential(user, "salesforce")
    {salesforce_info, salesforce_info_error} = fetch_salesforce_info(salesforce_credential)

    socket =
      socket
      |> assign(:page_title, "CRM Contact Debug")
      |> assign(:query, "")
      |> assign(:limit, 50)
      |> assign(:hubspot_credential, hubspot_credential)
      |> assign(:salesforce_credential, salesforce_credential)
      |> assign(:salesforce_info, salesforce_info)
      |> assign(:salesforce_info_error, salesforce_info_error)
      |> assign(:search_results, %{hubspot: [], salesforce: []})
      |> assign(:list_results, %{hubspot: [], salesforce: []})
      |> assign(:errors, %{
        hubspot_search: nil,
        salesforce_search: nil,
        hubspot_list: nil,
        salesforce_list: nil
      })

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    query = query |> to_string() |> String.trim()

    {hubspot_results, hubspot_error} =
      run_search(socket.assigns.hubspot_credential, query, &HubspotApi.search_contacts/2)

    {salesforce_results, salesforce_error} =
      run_search(socket.assigns.salesforce_credential, query, &SalesforceApi.search_contacts/2)

    errors =
      socket.assigns.errors
      |> Map.put(:hubspot_search, hubspot_error)
      |> Map.put(:salesforce_search, salesforce_error)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:search_results, %{hubspot: hubspot_results, salesforce: salesforce_results})
     |> assign(:errors, errors)}
  end

  @impl true
  def handle_event("list_all", %{"limit" => limit_param}, socket) do
    limit = parse_limit(limit_param, socket.assigns.limit)

    {hubspot_results, hubspot_error} =
      run_list(socket.assigns.hubspot_credential, limit, &HubspotApi.list_contacts/2)

    {salesforce_results, salesforce_error} =
      run_list(socket.assigns.salesforce_credential, limit, &SalesforceApi.list_contacts/2)

    errors =
      socket.assigns.errors
      |> Map.put(:hubspot_list, hubspot_error)
      |> Map.put(:salesforce_list, salesforce_error)

    {:noreply,
     socket
     |> assign(:limit, limit)
     |> assign(:list_results, %{hubspot: hubspot_results, salesforce: salesforce_results})
     |> assign(:errors, errors)}
  end

  defp fetch_salesforce_info(nil), do: {nil, nil}

  defp fetch_salesforce_info(credential) do
    case SalesforceApi.get_connection_info(credential) do
      {:ok, info} -> {info, nil}
      {:error, reason} -> {nil, format_error(reason)}
    end
  end

  defp run_search(nil, _query, _fun), do: {[], "Not connected"}
  defp run_search(_credential, "", _fun), do: {[], "Query is required"}

  defp run_search(credential, query, fun) do
    case fun.(credential, query) do
      {:ok, results} -> {sanitize_contacts(results), nil}
      {:error, reason} -> {[], format_error(reason)}
    end
  end

  defp run_list(nil, _limit, _fun), do: {[], "Not connected"}

  defp run_list(credential, limit, fun) do
    case fun.(credential, limit) do
      {:ok, results} -> {sanitize_contacts(results), nil}
      {:error, reason} -> {[], format_error(reason)}
    end
  end

  defp sanitize_contacts(contacts) when is_list(contacts) do
    Enum.reject(contacts, &is_nil/1)
  end

  defp sanitize_contacts(_), do: []

  defp parse_limit(value, fallback) do
    case Integer.parse(to_string(value || "")) do
      {int, ""} -> clamp(int, 1, 200)
      _ -> clamp(fallback, 1, 200)
    end
  end

  defp clamp(value, min_value, max_value) do
    value
    |> max(min_value)
    |> min(max_value)
  end

  defp format_error(reason), do: inspect(reason)

  defp contact_list(assigns) do
    assigns =
      assigns
      |> assign_new(:empty_message, fn -> "No results yet." end)

    ~H"""
    <div class="bg-white shadow-lg rounded-lg p-6">
      <div class="flex items-center justify-between">
        <h3 class="text-base font-semibold text-slate-800">{@title}</h3>
        <span class="text-xs text-slate-500">{length(@contacts)} results</span>
      </div>

      <%= if Enum.empty?(@contacts) do %>
        <p class="mt-3 text-xs text-slate-500">{@empty_message}</p>
      <% else %>
        <div class="mt-4 space-y-3">
          <div
            :for={contact <- @contacts}
            class="rounded-md border border-slate-200 bg-slate-50/50 px-3 py-2"
          >
            <div class="text-sm font-medium text-slate-800">
              {Map.get(contact, :display_name) || "Unknown"}
            </div>
            <div class="text-xs text-slate-500">
              {Map.get(contact, :email) || "no email"}
              <span class="text-slate-400">·</span>
              {Map.get(contact, :id) || "no id"}
            </div>
            <pre class="mt-2 text-[11px] text-slate-500 whitespace-pre-wrap"><%= inspect(contact, limit: 40, pretty: true) %></pre>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
