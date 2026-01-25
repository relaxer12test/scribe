defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth.
  """

  @pkce_session_key "salesforce_pkce_verifier"

  use Ueberauth.Strategy,
    uid_field: :user_id,
    default_scope: "api refresh_token",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Auth.Info

  @doc """
  Handles initial request for Salesforce authentication.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    redirect_uri = redirect_uri(conn)
    code_verifier = pkce_verifier()
    code_challenge = pkce_challenge(code_verifier)

    conn = put_session(conn, @pkce_session_key, code_verifier)

    opts =
      [
        scope: scopes,
        redirect_uri: redirect_uri,
        code_challenge: code_challenge,
        code_challenge_method: "S256",
        prompt: "consent"
      ]
      |> with_state_param(conn)

    redirect!(conn, Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(opts))
  end

  @doc """
  Handles the callback from Salesforce.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    code_verifier = get_session(conn, @pkce_session_key)
    conn = delete_session(conn, @pkce_session_key)
    opts = [redirect_uri: redirect_uri(conn)]
    params = token_params(code, code_verifier)

    case Ueberauth.Strategy.Salesforce.OAuth.get_access_token(params, opts) do
      {:ok, token} ->
        fetch_user(conn, token)

      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Cleans up the private area of the connection used for passing the raw Salesforce response around during the callback.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
  end

  @doc """
  Fetches the uid field from the response.
  """
  def uid(conn) do
    uid_field =
      conn
      |> option(:uid_field)
      |> to_string()

    conn.private.salesforce_user[uid_field]
  end

  @doc """
  Includes the credentials from the Salesforce response.
  """
  def credentials(conn) do
    token = conn.private.salesforce_token

    %Credentials{
      expires: true,
      expires_at: token.expires_at,
      scopes: String.split(token.other_params["scope"] || "", " "),
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.salesforce_user
    email = user["email"] || user["preferred_username"] || user["username"]
    name = user["name"] || user["display_name"] || user["preferred_username"] || email

    %Info{
      email: email,
      name: name
    }
  end

  @doc """
  Stores the raw information obtained from the Salesforce callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.salesforce_token,
        user: conn.private.salesforce_user
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :salesforce_token, token)

    case Ueberauth.Strategy.Salesforce.OAuth.get_user(token) do
      {:ok, user} ->
        put_private(conn, :salesforce_user, user)

      {:error, reason} ->
        set_errors!(conn, [error("user_info_error", reason)])
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  defp redirect_uri(conn) do
    oauth_config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    oauth_config[:redirect_uri] || callback_url(conn)
  end

  defp pkce_verifier do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp pkce_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end

  defp token_params(code, nil), do: [code: code]
  defp token_params(code, verifier), do: [code: code, code_verifier: verifier]
end
