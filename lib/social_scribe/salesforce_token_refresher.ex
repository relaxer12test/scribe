defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Refreshes Salesforce OAuth tokens.
  """

  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.UserCredential

  require Logger

  @token_path "/services/oauth2/token"

  def client do
    Tesla.client([
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON
    ])
  end

  @doc """
  Refreshes a Salesforce access token using the refresh token.
  Returns {:ok, response_body} with access_token and optional refresh_token/expires_in.
  """
  def refresh_token(refresh_token_string) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]
    site = Keyword.get(config, :site, "https://login.salesforce.com")

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string
    }

    case Tesla.post(client(), site <> @token_path, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes the token for a Salesforce credential and updates it in the database.
  """
  def refresh_credential(%UserCredential{} = credential) do
    cond do
      reauth_required?(credential) ->
        {:error, {:reauth_required, reauth_info(credential)}}

      missing_refresh_token?(credential) ->
        mark_reauth_required(credential, :missing_refresh_token)

      true ->
        case refresh_token(credential.refresh_token) do
          {:ok, response} ->
            expires_in = salesforce_expires_in(response)
            refresh_token = response["refresh_token"] || credential.refresh_token

            attrs = %{
              token: response["access_token"],
              refresh_token: refresh_token,
              expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second),
              reauth_required_at: nil
            }

            Accounts.update_user_credential(credential, attrs)

          {:error, reason} ->
            handle_refresh_error(credential, reason)
        end
    end
  end

  @doc """
  Ensures a credential has a valid (non-expired) token.
  Refreshes if expired or about to expire (within 5 minutes).
  """
  def ensure_valid_token(credential) do
    buffer_seconds = 300
    expires_at = credential.expires_at || DateTime.utc_now()

    cond do
      reauth_required?(credential) ->
        {:error, {:reauth_required, reauth_info(credential)}}

      DateTime.compare(expires_at, DateTime.add(DateTime.utc_now(), buffer_seconds, :second)) ==
          :lt ->
        refresh_credential(credential)

      true ->
        {:ok, credential}
    end
  end

  defp missing_refresh_token?(%UserCredential{} = credential) do
    refresh_token = credential.refresh_token
    is_nil(refresh_token) || refresh_token == ""
  end

  defp salesforce_expires_in(response) do
    case response["expires_in"] do
      expires_in when is_integer(expires_in) and expires_in > 0 ->
        expires_in

      expires_in when is_binary(expires_in) ->
        case Integer.parse(expires_in) do
          {value, _} when value > 0 -> value
          _ -> salesforce_default_expires_in()
        end

      _ ->
        salesforce_default_expires_in()
    end
  end

  defp salesforce_default_expires_in do
    Application.get_env(:social_scribe, :salesforce_token_ttl_seconds, 7200)
  end

  defp reauth_required?(%UserCredential{} = credential) do
    not is_nil(credential.reauth_required_at)
  end

  defp handle_refresh_error(%UserCredential{} = credential, {status, body})
       when status in [400, 401, 403] do
    if reauth_error?(body) do
      mark_reauth_required(credential, {status, body})
    else
      {:error, {status, body}}
    end
  end

  defp handle_refresh_error(_credential, reason), do: {:error, reason}

  defp reauth_error?(%{"error" => error}) when error in ["invalid_grant"], do: true

  defp reauth_error?(%{"error_description" => description}) when is_binary(description) do
    String.contains?(String.downcase(description), ["expired", "revoked"])
  end

  defp reauth_error?(%{"message" => message}) when is_binary(message) do
    String.contains?(String.downcase(message), ["expired", "revoked"])
  end

  defp reauth_error?(_), do: false

  defp mark_reauth_required(%UserCredential{} = credential, reason) do
    Logger.debug("Salesforce refresh requires reauth: #{inspect(reason)}")

    case Accounts.mark_user_credential_reauth_required(credential) do
      {:ok, updated} ->
        {:error, {:reauth_required, reauth_info(updated)}}

      {:error, changeset} ->
        Logger.error("Failed to mark Salesforce credential reauth required: #{inspect(changeset)}")
        {:error, {:reauth_required, reauth_info(credential)}}
    end
  end

  defp reauth_info(%UserCredential{} = credential) do
    %{
      id: credential.id,
      email: credential.email,
      uid: credential.uid
    }
  end
end
