defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  import Mox

  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures

  alias SocialScribe.SalesforceSuggestions

  setup :verify_on_exit!

  describe "generate_suggestions/3" do
    test "filters unchanged values and applies field labels" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture()

      contact = %{
        :id => "003",
        :firstname => "Pat",
        :lastname => "Doe",
        :email => "pat@example.com",
        "Phone" => "555-1234",
        "Title" => "CTO"
      }

      ai_suggestions = [
        %{field: "Phone", value: "555-1234", context: "Mentioned phone", timestamp: "00:10"},
        %{field: "Title", value: "VP", context: "Mentioned title", timestamp: "00:20"}
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn ^credential, "003" -> {:ok, contact} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn ^meeting -> {:ok, ai_suggestions} end)

      assert {:ok, %{contact: ^contact, suggestions: [suggestion]}} =
               SalesforceSuggestions.generate_suggestions(credential, "003", meeting)

      assert suggestion.field == "Title"
      assert suggestion.label == "Job Title"
      assert suggestion.current_value == "CTO"
      assert suggestion.new_value == "VP"
      assert suggestion.apply == true
      assert suggestion.has_change == true
    end

    test "returns error when contact lookup fails" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture()

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn ^credential, "003" -> {:error, :not_found} end)

      assert {:error, :not_found} =
               SalesforceSuggestions.generate_suggestions(credential, "003", meeting)
    end
  end

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "MailingCity",
          label: "Mailing City",
          current_value: nil,
          new_value: "Austin",
          context: "Lives in Austin",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        "Phone" => "555-1234",
        "MailingCity" => nil
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Only MailingCity should remain since Phone already matches
      assert length(result) == 1
      assert hd(result).field == "MailingCity"
      assert hd(result).new_value == "Austin"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "Email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        "Email" => "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{"Email" => "test@example.com"}

      result = SalesforceSuggestions.merge_with_contact([], contact)

      assert result == []
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{"Phone" => nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end
  end
end
