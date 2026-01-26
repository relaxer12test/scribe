defmodule SocialScribe.CrmProviders do
  @moduledoc false

  require Logger

  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.HubspotSuggestions
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.SalesforceSuggestions

  @providers [
    %{
      id: "hubspot",
      name: "HubSpot",
      api_module: HubspotApi,
      suggestions_module: HubspotSuggestions,
      suggestions_mode: :meeting_only,
      reauth: false,
      reauth_path: nil,
      card_title: "HubSpot Integration",
      card_description: "Update CRM contacts with information from this meeting",
      button_text: "Update HubSpot Contact",
      button_class:
        "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-orange-500 hover:bg-orange-600 transition-colors",
      submit_text: "Update HubSpot",
      submit_class: "bg-hubspot-button hover:bg-hubspot-button-hover",
      icon: :hubspot
    },
    %{
      id: "salesforce",
      name: "Salesforce",
      api_module: SalesforceApi,
      suggestions_module: SalesforceSuggestions,
      suggestions_mode: :with_contact,
      reauth: true,
      reauth_path: "/auth/salesforce?prompt=consent",
      card_title: "Salesforce Integration",
      card_description: "Update Salesforce contacts with information from this meeting",
      button_text: "Update Salesforce Contact",
      button_class:
        "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-sky-600 hover:bg-sky-700 transition-colors",
      submit_text: "Update Salesforce",
      submit_class: "bg-sky-600 hover:bg-sky-700",
      icon: :salesforce
    }
  ]

  @us_states [
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
    {"Wyoming", "WY"}
  ]
  @ca_provinces [
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
  @us_state_codes MapSet.new(Enum.map(@us_states, &elem(&1, 1)))
  @us_state_names MapSet.new(Enum.map(@us_states, fn {name, _code} -> String.downcase(name) end))
  @us_state_name_to_code Map.new(@us_states, fn {name, code} -> {String.downcase(name), code} end)
  @ca_province_codes MapSet.new(Enum.map(@ca_provinces, &elem(&1, 1)))
  @ca_province_names MapSet.new(Enum.map(@ca_provinces, fn {name, _code} -> String.downcase(name) end))
  @ca_province_name_to_code Map.new(@ca_provinces, fn {name, code} -> {String.downcase(name), code} end)

  def providers, do: @providers

  def provider_ids, do: Enum.map(@providers, & &1.id)

  def default_provider, do: List.first(@providers)
  def default_provider_id, do: default_provider().id

  def get(%{id: _} = provider), do: provider

  def get(provider) do
    case fetch(provider) do
      {:ok, config} -> config
      :error -> default_provider()
    end
  end

  def fetch(provider) do
    id = normalize_provider(provider)

    case Enum.find(@providers, &(&1.id == id)) do
      nil -> :error
      config -> {:ok, config}
    end
  end

  def normalize_provider(provider) when is_atom(provider),
    do: provider |> Atom.to_string() |> normalize_provider()

  def normalize_provider(provider) when is_binary(provider), do: String.downcase(provider)
  def normalize_provider(_), do: default_provider_id()

  def modal_id(provider), do: provider |> provider_id() |> Kernel.<>("-modal")
  def modal_wrapper_id(provider), do: provider |> provider_id() |> Kernel.<>("-modal-wrapper")

  def provider_id(%{id: id}), do: id
  def provider_id(provider), do: normalize_provider(provider)

  def reauth_required?(provider, credential) do
    config = get(provider)
    config.reauth && match?(%{reauth_required_at: %DateTime{}}, credential)
  end

  def search_contacts(provider, credential, query) do
    config = get(provider)
    apply(config.api_module, :search_contacts, [credential, query])
  end

  def generate_suggestions(provider, credential, contact, meeting) do
    config = get(provider)

    case config.suggestions_mode do
      :meeting_only ->
        with {:ok, suggestions} <- config.suggestions_module.generate_suggestions_from_meeting(meeting) do
          merged = config.suggestions_module.merge_with_contact(suggestions, contact)
          {:ok, %{contact: contact, suggestions: merged}}
        end

      :with_contact ->
        case contact_id(contact) do
          nil ->
            {:error, :missing_contact_id}

          contact_id_value ->
            config.suggestions_module.generate_suggestions(credential, contact_id_value, meeting)
        end

      _ ->
        {:error, :unsupported_provider}
    end
  end

  def apply_updates(provider, credential, contact, updates) do
    config = get(provider)

    case contact_id(contact) do
      nil ->
        {:error, :missing_contact_id}

      contact_id_value ->
        case normalize_updates(config, contact, updates) do
          {:ok, normalized_updates} ->
            apply(config.api_module, :update_contact, [credential, contact_id_value, normalized_updates])

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def contact_id(contact) when is_map(contact) do
    Map.get(contact, :id) || Map.get(contact, "id")
  end

  def contact_id(_), do: nil

  defp normalize_updates(%{id: "salesforce"}, contact, updates) when is_map(updates) do
    ensure_salesforce_state_country(contact, updates)
  end

  defp normalize_updates(_config, _contact, updates), do: {:ok, updates}

  defp ensure_salesforce_state_country(contact, updates) do
    state_value = Map.get(updates, "MailingStateCode") || Map.get(updates, "MailingState")
    state_code = salesforce_state_code(state_value)
    updates = maybe_put_state_code(updates, state_code)
    contact_country = salesforce_contact_country(contact)

    if present_value?(state_value) do
      country_value =
        Map.get(updates, "MailingCountryCode") ||
          Map.get(updates, "MailingCountry") ||
          contact_country ||
          infer_salesforce_country(state_value)

      country_code = salesforce_country_code(country_value) || infer_country_code_from_state(state_code)
      updates = maybe_put_country_code(updates, country_code)

      if present_value?(country_code) do
        log_salesforce_update_decision(contact, updates, "country_present_in_updates")
        {:ok, updates}
      else
        log_salesforce_update_decision(contact, updates, "missing_country")
        {:error, :missing_country_for_state}
      end
    else
      log_salesforce_update_decision(contact, updates, "no_state_update")
      {:ok, updates}
    end
  end

  defp salesforce_contact_country(contact) when is_map(contact) do
    Map.get(contact, "MailingCountry") || Map.get(contact, :mailing_country)
  end

  defp salesforce_contact_country(_), do: nil

  defp present_value?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_value?(_value), do: false

  defp salesforce_state_code(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      MapSet.member?(@us_state_codes, String.upcase(trimmed)) ->
        String.upcase(trimmed)

      MapSet.member?(@ca_province_codes, String.upcase(trimmed)) ->
        String.upcase(trimmed)

      true ->
        normalized = String.downcase(trimmed)

        Map.get(@us_state_name_to_code, normalized) ||
          Map.get(@ca_province_name_to_code, normalized)
    end
  end

  defp salesforce_state_code(_), do: nil

  defp maybe_put_state_code(updates, state_code) do
    if present_value?(state_code) do
      updates
      |> Map.put("MailingStateCode", state_code)
      |> Map.delete("MailingState")
    else
      updates
    end
  end

  defp salesforce_country_code(value) when is_binary(value) do
    trimmed = String.trim(value)
    normalized = String.downcase(trimmed)

    cond do
      trimmed == "" -> nil
      normalized in ["us", "usa", "united states", "united states of america"] -> "US"
      normalized in ["ca", "canada"] -> "CA"
      true -> nil
    end
  end

  defp salesforce_country_code(_), do: nil

  defp infer_country_code_from_state(state_code) when is_binary(state_code) do
    cond do
      MapSet.member?(@us_state_codes, String.upcase(state_code)) -> "US"
      MapSet.member?(@ca_province_codes, String.upcase(state_code)) -> "CA"
      true -> nil
    end
  end

  defp infer_country_code_from_state(_), do: nil

  defp maybe_put_country_code(updates, country_code) do
    if present_value?(country_code) do
      updates
      |> Map.put("MailingCountryCode", country_code)
      |> Map.delete("MailingCountry")
    else
      updates
    end
  end

  defp infer_salesforce_country(state_value) when is_binary(state_value) do
    trimmed = String.trim(state_value)

    cond do
      trimmed == "" ->
        nil

      MapSet.member?(@us_state_codes, String.upcase(trimmed)) ->
        "United States"

      MapSet.member?(@ca_province_codes, String.upcase(trimmed)) ->
        "Canada"

      true ->
        normalized = String.downcase(trimmed)

        cond do
          MapSet.member?(@us_state_names, normalized) -> "United States"
          MapSet.member?(@ca_province_names, normalized) -> "Canada"
          true -> nil
        end
    end
  end

  defp infer_salesforce_country(_), do: nil

  defp log_salesforce_update_decision(contact, updates, decision) do
    contact_id = contact_id(contact)
    state_value = Map.get(updates, "MailingState") || Map.get(updates, "MailingStateCode")
    country_value = Map.get(updates, "MailingCountry") || Map.get(updates, "MailingCountryCode")

    Logger.info(
      "salesforce_update_normalize decision=#{decision} contact_id=#{contact_id} " <>
        "state=#{inspect(state_value)} " <>
        "country=#{inspect(country_value)} " <>
        "contact_country=#{inspect(salesforce_contact_country(contact))}"
    )
  end
end
