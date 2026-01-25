defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  import SocialScribe.AccountsFixtures

  alias SocialScribe.SalesforceTokenRefresher

  setup do
    old_adapter = Application.get_env(:tesla, :adapter)
    old_oauth = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])

    Application.put_env(:tesla, :adapter, Tesla.Mock)

    Application.put_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
      site: "https://salesforce.test",
      client_id: "client_id",
      client_secret: "client_secret"
    )

    on_exit(fn ->
      if is_nil(old_adapter) do
        Application.delete_env(:tesla, :adapter)
      else
        Application.put_env(:tesla, :adapter, old_adapter)
      end

      Application.put_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, old_oauth)
    end)

    :ok
  end

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "refreshes when token is about to expire" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old-token",
          refresh_token: "old-refresh",
          expires_at: DateTime.add(DateTime.utc_now(), 60, :second)
        })

      Tesla.Mock.mock(fn env ->
        assert env.method == :post
        assert env.url == "https://salesforce.test/services/oauth2/token"

        %Tesla.Env{
          status: 200,
          body: %{
            "access_token" => "new-token",
            "refresh_token" => "new-refresh",
            "expires_in" => 7200
          }
        }
      end)

      {:ok, updated} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert updated.token == "new-token"
      assert updated.refresh_token == "new-refresh"
    end

    test "returns reauth_required when credential is already flagged" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          reauth_required_at: DateTime.utc_now()
        })

      assert {:error, {:reauth_required, info}} =
               SalesforceTokenRefresher.ensure_valid_token(credential)

      assert info.id == credential.id
    end

    test "returns reauth_required when refresh token is missing" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          refresh_token: nil,
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      assert {:error, {:reauth_required, info}} =
               SalesforceTokenRefresher.ensure_valid_token(credential)

      assert info.id == credential.id
    end
  end

  describe "refresh_token/1" do
    test "returns error on non-200 response" do
      Tesla.Mock.mock(fn env ->
        assert env.method == :post
        %Tesla.Env{status: 401, body: %{"error" => "invalid_grant"}}
      end)

      assert {:error, {401, %{"error" => "invalid_grant"}}} =
               SalesforceTokenRefresher.refresh_token("bad-refresh")
    end
  end

  describe "refresh_credential/1" do
    test "updates credential in database on successful refresh" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old-token",
          refresh_token: "old-refresh",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      Tesla.Mock.mock(fn env ->
        assert env.method == :post
        %Tesla.Env{status: 200, body: %{"access_token" => "new-token", "expires_in" => 3600}}
      end)

      {:ok, updated} = SalesforceTokenRefresher.refresh_credential(credential)

      assert updated.id == credential.id
      assert updated.token == "new-token"
      assert is_nil(updated.reauth_required_at)
    end

    test "marks credential when refresh token is invalid" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old-token",
          refresh_token: "bad-refresh",
          expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
        })

      Tesla.Mock.mock(fn env ->
        assert env.method == :post
        %Tesla.Env{status: 400, body: %{"error" => "invalid_grant"}}
      end)

      assert {:error, {:reauth_required, info}} =
               SalesforceTokenRefresher.refresh_credential(credential)

      assert info.id == credential.id
    end
  end
end
