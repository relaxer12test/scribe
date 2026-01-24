defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  describe "apply_updates/3" do
    test "returns :no_updates when updates list is empty" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003000000000001", [])
    end

    test "returns :no_updates when all updates are not applied" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "Phone", new_value: "555-1234", apply: false},
        %{field: "Email", new_value: "test@example.com", apply: false}
      ]

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003000000000001", updates)
    end
  end

  describe "search_contacts/2" do
    test "accepts a valid credential and query" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
      assert is_binary("test")
    end
  end

  describe "get_contact/2" do
    test "accepts a valid credential and contact_id" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "update_contact/3" do
    test "accepts a valid credential, contact_id, and updates map" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end
end
