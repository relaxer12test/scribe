defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on auth errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @api_version "v58.0"

  @contact_fields [
    "Id",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry"
  ]

  defp client(access_token, base_url) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string.
  Returns up to 10 matching contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      {:ok, []}
    else
      with_token_refresh(credential, fn cred ->
        with_instance_url(cred, fn instance_url ->
          soql = build_search_query(query)
          url = "/services/data/#{@api_version}/query?q=#{URI.encode(soql)}"

          case Tesla.get(client(cred.token, instance_url), url) do
            {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
              contacts = Enum.map(records, &format_contact/1)
              {:ok, contacts}

            {:ok, %Tesla.Env{status: status, body: body}} ->
              {:error, {:api_error, status, body}}

            {:error, reason} ->
              {:error, {:http_error, reason}}
          end
        end)
      end)
    end
  end

  @doc """
  Lists recent contacts.
  Returns up to `limit` contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def list_contacts(%UserCredential{} = credential, limit \\ 50) when is_integer(limit) do
    limit = limit |> max(1) |> min(200)

    with_token_refresh(credential, fn cred ->
      with_instance_url(cred, fn instance_url ->
        fields = Enum.join(@contact_fields, ", ")
        soql = "SELECT #{fields} FROM Contact ORDER BY LastModifiedDate DESC LIMIT #{limit}"
        url = "/services/data/#{@api_version}/query?q=#{URI.encode(soql)}"

        case Tesla.get(client(cred.token, instance_url), url) do
          {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
            contacts = Enum.map(records, &format_contact/1)
            {:ok, contacts}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end)
    end)
  end

  @doc """
  Gets a single contact by ID with selected properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def get_contact(%UserCredential{} = credential, contact_id) when is_binary(contact_id) do
    with_token_refresh(credential, fn cred ->
      with_instance_url(cred, fn instance_url ->
        soql = build_contact_query(contact_id)
        url = "/services/data/#{@api_version}/query?q=#{URI.encode(soql)}"

        case Tesla.get(client(cred.token, instance_url), url) do
          {:ok, %Tesla.Env{status: 200, body: %{"records" => [record | _]}}} ->
            {:ok, format_contact(record)}

          {:ok, %Tesla.Env{status: 200, body: %{"records" => []}}} ->
            {:error, :not_found}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end)
    end)
  end

  @doc """
  Updates a contact's properties.
  `updates` should be a map of Salesforce field names to new values.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) and is_binary(contact_id) do
    state_value = Map.get(updates, "MailingState") || Map.get(updates, "MailingStateCode")
    country_value = Map.get(updates, "MailingCountry") || Map.get(updates, "MailingCountryCode")

    Logger.info(
      "salesforce_update_contact contact_id=#{contact_id} fields=#{inspect(Map.keys(updates))} " <>
        "state=#{inspect(state_value)} country=#{inspect(country_value)}"
    )

    with_token_refresh(credential, fn cred ->
      with_instance_url(cred, fn instance_url ->
        url = "/services/data/#{@api_version}/sobjects/Contact/#{contact_id}"

        case Tesla.patch(client(cred.token, instance_url), url, updates) do
          {:ok, %Tesla.Env{status: 204}} ->
            {:ok, %{id: contact_id}}

          {:ok, %Tesla.Env{status: 200, body: body}} ->
            {:ok, Map.put(body, "id", contact_id)}

          {:ok, %Tesla.Env{status: 404, body: _body}} ->
            {:error, :not_found}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            Logger.warning(
              "salesforce_update_contact_failed contact_id=#{contact_id} status=#{status} body=#{inspect(body)}"
            )
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            Logger.warning(
              "salesforce_update_contact_http_error contact_id=#{contact_id} reason=#{inspect(reason)}"
            )
            {:error, {:http_error, reason}}
        end
      end)
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  This is a convenience wrapper around update_contact/3.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  @doc """
  Fetches Salesforce connection info for the current credential.
  Returns instance_url, org_id, and user_id when available.
  """
  def get_connection_info(%UserCredential{} = credential) do
    with_token_refresh(credential, fn cred ->
      case fetch_userinfo(cred) do
        {:ok, body} ->
          case instance_url_from_userinfo(body) do
            {:ok, instance_url} ->
              {:ok,
               %{
                 instance_url: instance_url,
                 org_id: body["organization_id"],
                 user_id: body["user_id"]
               }}

            :error ->
              {:error, {:missing_instance_url, body}}
          end

        {:error, _} = error ->
          error
      end
    end)
  end

  defp build_search_query(query) do
    escaped = escape_soql_like(query)
    fields = Enum.join(@contact_fields, ", ")

    "SELECT #{fields} FROM Contact " <>
      "WHERE (Name LIKE '%#{escaped}%' OR Email LIKE '%#{escaped}%' " <>
      "OR Phone LIKE '%#{escaped}%' OR MobilePhone LIKE '%#{escaped}%') " <>
      "ORDER BY LastModifiedDate DESC LIMIT 10"
  end

  defp build_contact_query(contact_id) do
    escaped = escape_soql_value(contact_id)
    fields = Enum.join(@contact_fields, ", ")
    "SELECT #{fields} FROM Contact WHERE Id = '#{escaped}' LIMIT 1"
  end

  defp escape_soql_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\\\'")
    |> String.replace("%", "\\\\%")
    |> String.replace("_", "\\\\_")
  end

  defp escape_soql_value(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\\\'")
  end

  defp with_instance_url(%UserCredential{} = credential, api_call) do
    case fetch_instance_url(credential) do
      {:ok, instance_url} -> api_call.(instance_url)
      {:error, _} = error -> error
    end
  end

  defp fetch_instance_url(%UserCredential{} = credential) do
    case fetch_userinfo(credential) do
      {:ok, body} ->
        case instance_url_from_userinfo(body) do
          {:ok, instance_url} -> {:ok, instance_url}
          :error -> {:error, {:missing_instance_url, body}}
        end

      {:error, _} = error ->
        error
    end
  end

  defp fetch_userinfo(%UserCredential{} = credential) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    site = Keyword.get(config, :site, "https://login.salesforce.com")
    url = site <> "/services/oauth2/userinfo"

    case Tesla.get(userinfo_client(credential.token), url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp userinfo_client(access_token) do
    Tesla.client([
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{access_token}"}]}
    ])
  end

  defp instance_url_from_userinfo(%{"instance_url" => instance_url})
       when is_binary(instance_url) do
    {:ok, instance_url}
  end

  defp instance_url_from_userinfo(%{"urls" => urls} = body) when is_map(urls) do
    candidates = [
      urls["custom_domain"],
      urls["rest"],
      urls["sobjects"],
      urls["query"],
      urls["search"],
      urls["tooling_rest"],
      urls["tooling_soap"],
      body["profile"]
    ]

    case extract_base_url(candidates) do
      nil -> :error
      instance_url -> {:ok, instance_url}
    end
  end

  defp instance_url_from_userinfo(%{"profile" => profile}) when is_binary(profile) do
    case base_from_url(profile) do
      nil -> :error
      instance_url -> {:ok, instance_url}
    end
  end

  defp instance_url_from_userinfo(_), do: :error

  defp extract_base_url(candidates) when is_list(candidates) do
    Enum.find_value(candidates, fn url ->
      case base_from_url(url) do
        nil -> false
        base -> base
      end
    end)
  end

  defp base_from_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port}
      when is_binary(scheme) and is_binary(host) ->
        if port && port not in [80, 443] do
          "#{scheme}://#{host}:#{port}"
        else
          "#{scheme}://#{host}"
        end

      _ ->
        nil
    end
  end

  defp base_from_url(_), do: nil

  # Format a Salesforce contact response into a cleaner structure
  defp format_contact(%{"Id" => id} = record) do
    fields = %{
      "FirstName" => record["FirstName"],
      "LastName" => record["LastName"],
      "Email" => record["Email"],
      "Phone" => record["Phone"],
      "MobilePhone" => record["MobilePhone"],
      "Title" => record["Title"],
      "MailingStreet" => record["MailingStreet"],
      "MailingCity" => record["MailingCity"],
      "MailingState" => record["MailingState"],
      "MailingPostalCode" => record["MailingPostalCode"],
      "MailingCountry" => record["MailingCountry"]
    }

    base = %{
      id: id,
      firstname: fields["FirstName"],
      lastname: fields["LastName"],
      email: fields["Email"],
      phone: fields["Phone"],
      mobilephone: fields["MobilePhone"],
      title: fields["Title"],
      mailing_street: fields["MailingStreet"],
      mailing_city: fields["MailingCity"],
      mailing_state: fields["MailingState"],
      mailing_postal_code: fields["MailingPostalCode"],
      mailing_country: fields["MailingCountry"],
      display_name: format_display_name(fields)
    }

    Map.merge(base, fields)
  end

  defp format_contact(_), do: nil

  defp format_display_name(fields) do
    firstname = fields["FirstName"] || ""
    lastname = fields["LastName"] || ""
    email = fields["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  # Wrapper that handles token refresh on auth errors
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, status, body}} when status in [401, 403] ->
          if is_token_error?(body) do
            Logger.info("Salesforce token expired, refreshing and retrying...")
            retry_with_fresh_token(credential, api_call)
          else
            Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, {:reauth_required, _info} = error} ->
        Logger.debug("Salesforce refresh requires reauth.")
        {:error, error}

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?([%{"errorCode" => "INVALID_SESSION_ID"} | _]), do: true
  defp is_token_error?(%{"errorCode" => "INVALID_SESSION_ID"}), do: true
  defp is_token_error?(%{"error" => "invalid_session_id"}), do: true
  defp is_token_error?(%{"message" => msg}) when is_binary(msg) do
    String.contains?(String.downcase(msg), ["session", "expired", "invalid"])
  end
  defp is_token_error?(_), do: false
end
