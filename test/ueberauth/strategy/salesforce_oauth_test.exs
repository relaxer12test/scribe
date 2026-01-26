defmodule Ueberauth.Strategy.Salesforce.OAuthTest do
  use ExUnit.Case, async: false

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

  test "authorize_url!/2 builds a Salesforce authorize URL" do
    url = OAuth.authorize_url!(scope: "api")
    uri = URI.parse(url)
    params = URI.decode_query(uri.query)

    assert uri.host == "salesforce.test"
    assert uri.path == "/services/oauth2/authorize"
    assert params["client_id"] == "client-id"
    assert params["response_type"] == "code"
    assert params["redirect_uri"] == "http://localhost/callback"
    assert params["scope"] == "api"
  end

  test "get_access_token/2 returns OAuth2 token on success" do
    Tesla.Mock.mock(fn env ->
      assert env.method == :post
      assert env.url == "https://salesforce.test/services/oauth2/token"

      params = URI.decode_query(env.body)

      assert params["client_id"] == "client-id"
      assert params["client_secret"] == "client-secret"
      assert params["code"] == "auth-code"
      assert params["grant_type"] == "authorization_code"
      assert params["redirect_uri"] == "http://localhost/callback"

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
            "id" => "https://salesforce.test/id"
          })
      }
    end)

    assert {:ok, token} = OAuth.get_access_token(code: "auth-code")
    assert token.access_token == "access-token"
    assert token.refresh_token == "refresh-token"
    assert token.other_params["id"] == "https://salesforce.test/id"
  end

  test "get_access_token/2 maps error responses" do
    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{
        status: 400,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{"error" => "invalid_grant", "error_description" => "bad code"})
      }
    end)

    assert {:error, {"invalid_grant", "bad code"}} = OAuth.get_access_token(code: "bad-code")
  end

  test "get_user/1 fetches user info from token id url" do
    token = %OAuth2.AccessToken{
      access_token: "access-token",
      other_params: %{"id" => "https://salesforce.test/userinfo"}
    }

    Tesla.Mock.mock(fn env ->
      assert env.url == "https://salesforce.test/userinfo"
      assert {"authorization", "Bearer access-token"} in env.headers

      %Tesla.Env{
        status: 200,
        body: %{"user_id" => "user-123", "email" => "user@example.com"}
      }
    end)

    assert {:ok, %{"user_id" => "user-123"}} = OAuth.get_user(token)
  end

  test "get_user/1 returns error on non-200 response" do
    token = %OAuth2.AccessToken{
      access_token: "access-token",
      other_params: %{"id" => "https://salesforce.test/userinfo"}
    }

    Tesla.Mock.mock(fn _env ->
      %Tesla.Env{status: 500, body: %{"error" => "server_error"}}
    end)

    assert {:error, reason} = OAuth.get_user(token)
    assert reason =~ "Failed to get user info"
  end
end
