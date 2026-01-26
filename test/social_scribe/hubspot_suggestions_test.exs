defmodule SocialScribe.HubspotSuggestionsTest do
  use SocialScribe.DataCase

  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures

  alias SocialScribe.HubspotSuggestions

  setup :verify_on_exit!

  describe "generate_suggestions/3" do
    test "sets apply to false and filters unchanged values" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture()

      contact = %{
        id: "123",
        firstname: "Pat",
        lastname: "Doe",
        email: "pat@example.com",
        phone: "555-1234"
      }

      ai_suggestions = [
        %{field: "phone", value: "555-1234", context: "Mentioned phone", timestamp: "00:10"},
        %{field: "company", value: "Acme", context: "Works at Acme", timestamp: "00:20"}
      ]

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn ^credential, "123" -> {:ok, contact} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn ^meeting -> {:ok, ai_suggestions} end)

      assert {:ok, %{contact: ^contact, suggestions: [suggestion]}} =
               HubspotSuggestions.generate_suggestions(credential, "123", meeting)

      assert suggestion.field == "company"
      assert suggestion.label == "Company"
      assert suggestion.current_value == nil
      assert suggestion.new_value == "Acme"
      assert suggestion.apply == false
      assert suggestion.has_change == true
    end

    test "returns error when contact lookup fails" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture()

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn ^credential, "123" -> {:error, :not_found} end)

      assert {:error, :not_found} =
               HubspotSuggestions.generate_suggestions(credential, "123", meeting)
    end
  end

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "company",
          label: "Company",
          current_value: nil,
          new_value: "Acme Corp",
          context: "Works at Acme",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        phone: nil,
        company: "Acme Corp",
        email: "test@example.com"
      }

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since company already matches
      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        email: "test@example.com"
      }

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "123", email: "test@example.com"}

      result = HubspotSuggestions.merge_with_contact([], contact)

      assert result == []
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", phone: nil}

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end
  end
end
