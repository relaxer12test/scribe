defmodule SocialScribe.CrmProviders do
  @moduledoc false

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
        apply(config.api_module, :update_contact, [credential, contact_id_value, updates])
    end
  end

  def contact_id(contact) when is_map(contact) do
    Map.get(contact, :id) || Map.get(contact, "id")
  end

  def contact_id(_), do: nil
end
