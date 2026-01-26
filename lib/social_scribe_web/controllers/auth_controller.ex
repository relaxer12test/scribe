defmodule SocialScribeWeb.AuthController do
  use SocialScribeWeb, :controller

  alias SocialScribe.FacebookApi
  alias SocialScribe.Accounts
  alias SocialScribeWeb.UserAuth

  @salesforce_return_to_key :salesforce_return_to

  plug :store_salesforce_return_to when action in [:request]
  plug Ueberauth

  require Logger

  @doc """
  Handles the initial request to the provider (e.g., Google).
  Ueberauth's plug will redirect the user to the provider's consent page.
  """
  def request(conn, _params) do
    render(conn, :request)
  end

  @doc """
  Handles the callback from the provider after the user has granted consent.
  """
  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "google"
      })
      when not is_nil(user) do
    Logger.info("Google OAuth")
    Logger.info(auth)

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, _credential} ->
        conn
        |> put_flash(:info, "Google account added successfully.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not add Google account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "linkedin"
      }) do
    Logger.info("LinkedIn OAuth")
    Logger.info(auth)

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, credential} ->
        Logger.info("credential")
        Logger.info(credential)

        conn
        |> put_flash(:info, "LinkedIn account added successfully.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error(reason)

        conn
        |> put_flash(:error, "Could not add LinkedIn account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "facebook"
      })
      when not is_nil(user) do
    Logger.info("Facebook OAuth")
    Logger.info(auth)

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, credential} ->
        case FacebookApi.fetch_user_pages(credential.uid, credential.token) do
          {:ok, facebook_pages} ->
            facebook_pages
            |> Enum.each(fn page ->
              Accounts.link_facebook_page(user, credential, page)
            end)

          _ ->
            :ok
        end

        conn
        |> put_flash(
          :info,
          "Facebook account added successfully. Please select a page to connect."
        )
        |> redirect(to: ~p"/dashboard/settings/facebook_pages")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not add Facebook account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "hubspot"
      })
      when not is_nil(user) do
    Logger.info("HubSpot OAuth")
    Logger.info(inspect(auth))

    hub_id = to_string(auth.uid)

    credential_attrs = %{
      user_id: user.id,
      provider: "hubspot",
      uid: hub_id,
      token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }

    case Accounts.find_or_create_hubspot_credential(user, credential_attrs) do
      {:ok, _credential} ->
        Logger.info("HubSpot account connected for user #{user.id}, hub_id: #{hub_id}")

        conn
        |> put_flash(:info, "HubSpot account connected successfully!")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error("Failed to save HubSpot credential: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not connect HubSpot account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "salesforce"
      })
      when not is_nil(user) do
    {conn, return_to} = pop_salesforce_return_to(conn)
    destination = return_to || ~p"/dashboard/settings"

    Logger.info("Salesforce OAuth")
    Logger.info(inspect(auth))

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, _credential} ->
        conn
        |> put_flash(:info, "Salesforce account connected successfully!")
        |> redirect(to: destination)

      {:error, reason} ->
        Logger.error("Failed to save Salesforce credential: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not connect Salesforce account.")
        |> redirect(to: destination)
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    Logger.info("Google OAuth Login")
    Logger.info(auth)

    case Accounts.find_or_create_user_from_oauth(auth) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)

      {:error, reason} ->
        Logger.info("error")
        Logger.info(reason)

        conn
        |> put_flash(:error, "There was an error signing you in.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(conn, _params) do
    Logger.error("OAuth Login")
    Logger.error(conn)

    conn
    |> put_flash(:error, "There was an error signing you in. Please try again.")
    |> redirect(to: ~p"/")
  end

  defp store_salesforce_return_to(%{params: %{"provider" => "salesforce"}} = conn, _opts) do
    case fetch_salesforce_return_to(conn) do
      nil -> conn
      return_to -> put_session(conn, @salesforce_return_to_key, return_to)
    end
  end

  defp store_salesforce_return_to(conn, _opts), do: conn

  defp pop_salesforce_return_to(conn) do
    return_to = get_session(conn, @salesforce_return_to_key)
    {delete_session(conn, @salesforce_return_to_key), return_to}
  end

  defp fetch_salesforce_return_to(conn) do
    case conn.params["return_to"] do
      return_to when is_binary(return_to) ->
        if valid_return_to?(return_to), do: return_to, else: nil

      _ ->
        conn
        |> get_req_header("referer")
        |> List.first()
        |> return_to_from_referer(conn)
    end
  end

  defp return_to_from_referer(nil, _conn), do: nil

  defp return_to_from_referer(referer, conn) do
    referer
    |> URI.parse()
    |> return_to_from_uri(conn)
  end

  defp return_to_from_uri(%URI{} = uri, conn) do
    if same_origin?(uri, conn) && valid_return_path?(uri.path) do
      build_return_to(uri)
    end
  end

  defp build_return_to(%URI{path: path, query: query}) do
    if query && query != "", do: "#{path}?#{query}", else: path
  end

  defp same_origin?(%URI{host: host, port: port}, conn) do
    host == conn.host && (is_nil(port) || port == conn.port)
  end

  defp valid_return_to?(return_to) do
    case URI.parse(return_to) do
      %URI{scheme: nil, host: nil, path: path} -> valid_return_path?(path)
      _ -> false
    end
  end

  defp valid_return_path?(path) when is_binary(path) do
    String.starts_with?(path, "/") and
      not String.starts_with?(path, "//") and
      not String.starts_with?(path, "/auth")
  end

  defp valid_return_path?(_path), do: false
end
