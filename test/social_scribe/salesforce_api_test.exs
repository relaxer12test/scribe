defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  import SocialScribe.AccountsFixtures

  alias SocialScribe.SalesforceApi

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

  describe "apply_updates/3" do
    test "returns :no_updates when updates list is empty" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003000000000001", [])
    end

    test "returns :no_updates when all updates are not applied" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "Phone", new_value: "555-1234", apply: false},
        %{field: "Email", new_value: "test@example.com", apply: false}
      ]

      assert {:ok, :no_updates} =
               SalesforceApi.apply_updates(credential, "003000000000001", updates)
    end

    test "applies only selected updates" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "Phone", new_value: "555-1234", apply: true},
        %{field: "Email", new_value: "test@example.com", apply: false}
      ]

      Tesla.Mock.mock(fn env ->
        cond do
          env.url == "https://salesforce.test/services/oauth2/userinfo" ->
            %Tesla.Env{status: 200, body: %{"instance_url" => "https://instance.salesforce.test"}}

          env.method == :patch &&
              env.url ==
                "https://instance.salesforce.test/services/data/v58.0/sobjects/Contact/003" ->
            assert env.body == %{"Phone" => "555-1234"}
            %Tesla.Env{status: 204}

          true ->
            flunk("unexpected request: #{env.method} #{env.url}")
        end
      end)

      assert {:ok, %{id: "003"}} = SalesforceApi.apply_updates(credential, "003", updates)
    end
  end

  describe "search_contacts/2" do
    test "returns empty list for blank query" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      Tesla.Mock.mock(fn _env ->
        flunk("search should not call Salesforce for blank query")
      end)

      assert {:ok, []} = SalesforceApi.search_contacts(credential, "   ")
    end

    test "formats search results" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      Tesla.Mock.mock(fn env ->
        cond do
          env.url == "https://salesforce.test/services/oauth2/userinfo" ->
            %Tesla.Env{status: 200, body: %{"instance_url" => "https://instance.salesforce.test"}}

          String.starts_with?(env.url, "https://instance.salesforce.test/services/data/v58.0/query") ->
            %URI{query: query} = URI.parse(env.url)
            %{"q" => soql} = URI.decode_query(query)

            assert String.contains?(soql, "FROM Contact")
            assert String.contains?(soql, "Jane")

            %Tesla.Env{
              status: 200,
              body: %{
                "records" => [
                  %{
                    "Id" => "0031",
                    "FirstName" => "Jane",
                    "LastName" => "Doe",
                    "Email" => "jane@example.com"
                  }
                ]
              }
            }

          true ->
            flunk("unexpected request: #{env.method} #{env.url}")
        end
      end)

      assert {:ok, [contact]} = SalesforceApi.search_contacts(credential, "Jane")
      assert contact.id == "0031"
      assert contact.display_name == "Jane Doe"
      assert contact.email == "jane@example.com"
    end
  end

  describe "get_contact/2" do
    test "returns not_found when no records are returned" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      Tesla.Mock.mock(fn env ->
        cond do
          env.url == "https://salesforce.test/services/oauth2/userinfo" ->
            %Tesla.Env{status: 200, body: %{"instance_url" => "https://instance.salesforce.test"}}

          String.starts_with?(env.url, "https://instance.salesforce.test/services/data/v58.0/query") ->
            %Tesla.Env{status: 200, body: %{"records" => []}}

          true ->
            flunk("unexpected request: #{env.method} #{env.url}")
        end
      end)

      assert {:error, :not_found} = SalesforceApi.get_contact(credential, "003")
    end
  end

  describe "update_contact/3" do
    test "sends patch request and returns contact id" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      updates = %{"Phone" => "555-1234"}

      Tesla.Mock.mock(fn env ->
        cond do
          env.url == "https://salesforce.test/services/oauth2/userinfo" ->
            %Tesla.Env{status: 200, body: %{"instance_url" => "https://instance.salesforce.test"}}

          env.method == :patch &&
              env.url ==
                "https://instance.salesforce.test/services/data/v58.0/sobjects/Contact/003" ->
            assert env.body == updates
            %Tesla.Env{status: 204}

          true ->
            flunk("unexpected request: #{env.method} #{env.url}")
        end
      end)

      assert {:ok, %{id: "003"}} = SalesforceApi.update_contact(credential, "003", updates)
    end
  end

  describe "get_connection_info/1" do
    test "returns instance_url and ids" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      Tesla.Mock.mock(fn env ->
        assert env.url == "https://salesforce.test/services/oauth2/userinfo"

        %Tesla.Env{
          status: 200,
          body: %{
            "instance_url" => "https://instance.salesforce.test",
            "organization_id" => "org-123",
            "user_id" => "user-456"
          }
        }
      end)

      assert {:ok, info} = SalesforceApi.get_connection_info(credential)
      assert info.instance_url == "https://instance.salesforce.test"
      assert info.org_id == "org-123"
      assert info.user_id == "user-456"
    end
  end
end
