defmodule Ueberauth.Strategy.SalesforceTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Phoenix.ConnTest

  alias Ueberauth.Strategy.Salesforce
  alias Ueberauth.Strategy.Salesforce.OAuth

  setup do
    old_oauth = Application.get_env(:ueberauth, OAuth, [])
    old_oauth_adapter = Application.get_env(:oauth2, :adapter)
    old_tesla_adapter = Application.get_env(:tesla, :adapter)

    Application.put_env(:ueberauth, OAuth,
      client_id: "client-id",
      client_secret: "client-secret",
      site: "https://salesforce.test",
      redirect_uri: "http://localhost/callback"
    )

    Application.put_env(:oauth2, :adapter, Tesla.Mock)
    Application.put_env(:tesla, :adapter, Tesla.Mock)

    on_exit(fn ->
      Application.put_env(:ueberauth, OAuth, old_oauth)

      if is_nil(old_oauth_adapter) do
        Application.delete_env(:oauth2, :adapter)
      else
        Application.put_env(:oauth2, :adapter, old_oauth_adapter)
      end

      if is_nil(old_tesla_adapter) do
        Application.delete_env(:tesla, :adapter)
      else
        Application.put_env(:tesla, :adapter, old_tesla_adapter)
      end
    end)

    :ok
  end

  test "handle_request!/1 sets PKCE verifier and redirects" do
    conn =
      Plug.Test.conn(:get, "/auth/salesforce")
      |> init_test_session(%{})
      |> fetch_query_params()
      |> put_private(:ueberauth_request_options, [options: []])
      |> Salesforce.handle_request!()

    [location] = get_resp_header(conn, "location")
    uri = URI.parse(location)
    params = URI.decode_query(uri.query)

    assert uri.host == "salesforce.test"
    assert uri.path == "/services/oauth2/authorize"
    assert params["scope"] == "api refresh_token"
    assert params["prompt"] == "consent"
    assert params["code_challenge_method"] == "S256"

    verifier = get_session(conn, "salesforce_pkce_verifier")
    assert is_binary(verifier) and verifier != ""

    expected_challenge =
      :crypto.hash(:sha256, verifier)
      |> Base.url_encode64(padding: false)

    assert params["code_challenge"] == expected_challenge
  end

  test "handle_callback!/1 stores user and credentials on success" do
    conn =
      Plug.Test.conn(:get, "/auth/salesforce/callback", %{"code" => "auth-code"})
      |> init_test_session(%{})
      |> put_private(:ueberauth_request_options, [options: []])
      |> put_session("salesforce_pkce_verifier", "verifier")

    Tesla.Mock.mock(fn env ->
      cond do
        env.url == "https://salesforce.test/services/oauth2/token" ->
          params = URI.decode_query(env.body)
          assert params["code"] == "auth-code"
          assert params["code_verifier"] == "verifier"

          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/json"}],
            body:
              Jason.encode!(%{
                "access_token" => "access-token",
                "refresh_token" => "refresh-token",
                "expires_in" => 3600,
                "token_type" => "Bearer",
                "scope" => "api refresh_token",
                "id" => "https://salesforce.test/userinfo"
              })
          }

        env.url == "https://salesforce.test/userinfo" ->
          %Tesla.Env{
            status: 200,
            body: %{
              "user_id" => "user-123",
              "email" => "user@example.com",
              "name" => "User Example"
            }
          }

        true ->
          %Tesla.Env{status: 500, body: %{}}
      end
    end)

    conn = Salesforce.handle_callback!(conn)

    assert get_session(conn, "salesforce_pkce_verifier") == nil
    assert Salesforce.uid(conn) == "user-123"

    credentials = Salesforce.credentials(conn)
    assert credentials.token == "access-token"
    assert credentials.refresh_token == "refresh-token"
    assert credentials.scopes == ["api", "refresh_token"]

    info = Salesforce.info(conn)
    assert info.email == "user@example.com"
    assert info.name == "User Example"

    extra = Salesforce.extra(conn)
    assert extra.raw_info.user["user_id"] == "user-123"
  end

  test "handle_callback!/1 sets error when code is missing" do
    conn =
      Plug.Test.conn(:get, "/auth/salesforce/callback")
      |> init_test_session(%{})
      |> put_private(:ueberauth_request_options, [options: []])
      |> Salesforce.handle_callback!()

    failure = conn.assigns.ueberauth_failure
    assert failure
    assert Enum.any?(failure.errors, &(&1.message_key == "missing_code"))
  end
end
