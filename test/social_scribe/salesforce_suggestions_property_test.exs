defmodule SocialScribe.SalesforceSuggestionsPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SocialScribe.SalesforceSuggestions

  @salesforce_fields [
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "MobilePhone",
    "Title",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry"
  ]

  describe "merge_with_contact/2 properties" do
    property "never returns suggestions where new_value equals contact's current value" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 1, max_length: 5),
                contact <- contact_generator() do
        result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

        for suggestion <- result do
          current_in_contact = get_contact_value(contact, suggestion.field)
          refute suggestion.new_value == current_in_contact,
                 "Suggestion for #{suggestion.field} should have been filtered out: " <>
                   "new_value=#{inspect(suggestion.new_value)}, contact_value=#{inspect(current_in_contact)}"
        end
      end
    end

    property "all returned suggestions have has_change set to true" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 1, max_length: 5),
                contact <- contact_generator() do
        result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

        for suggestion <- result do
          assert suggestion.has_change == true,
                 "Suggestion for #{suggestion.field} should have has_change: true"
        end
      end
    end

    property "all returned suggestions have apply set to false" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 1, max_length: 5),
                contact <- contact_generator() do
        result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

        for suggestion <- result do
          assert suggestion.apply == false,
                 "Suggestion for #{suggestion.field} should have apply: false"
        end
      end
    end

    property "output length is always less than or equal to input length" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
                contact <- contact_generator() do
        result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

        assert length(result) <= length(suggestions),
               "Output length #{length(result)} should be <= input length #{length(suggestions)}"
      end
    end

    property "current_value in result matches the contact's actual value for that field" do
      check all suggestions <- list_of(suggestion_generator(), min_length: 1, max_length: 5),
                contact <- contact_generator() do
        result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

        for suggestion <- result do
          expected_current = get_contact_value(contact, suggestion.field)

          assert suggestion.current_value == expected_current,
                 "current_value for #{suggestion.field} should be #{inspect(expected_current)}, " <>
                   "got #{inspect(suggestion.current_value)}"
        end
      end
    end

    property "empty suggestions list returns empty list" do
      check all contact <- contact_generator() do
        result = SalesforceSuggestions.merge_with_contact([], contact)
        assert result == []
      end
    end
  end

  # Generators

  defp suggestion_generator do
    gen all field <- member_of(@salesforce_fields),
            new_value <- one_of([string(:alphanumeric, min_length: 1, max_length: 50), constant(nil)]),
            context <- string(:alphanumeric, min_length: 5, max_length: 100) do
      %{
        field: field,
        label: field,
        current_value: nil,
        new_value: new_value,
        context: context,
        apply: false,
        has_change: true
      }
    end
  end

  defp contact_generator do
    gen all first_name <- one_of([string(:alphanumeric, min_length: 1, max_length: 20), constant(nil)]),
            last_name <- one_of([string(:alphanumeric, min_length: 1, max_length: 20), constant(nil)]),
            email <- one_of([email_generator(), constant(nil)]),
            phone <- one_of([phone_generator(), constant(nil)]),
            mobile_phone <- one_of([phone_generator(), constant(nil)]),
            title <- one_of([string(:alphanumeric, min_length: 1, max_length: 30), constant(nil)]),
            mailing_city <- one_of([string(:alphanumeric, min_length: 1, max_length: 30), constant(nil)]),
            mailing_state <- one_of([string(:alphanumeric, min_length: 1, max_length: 30), constant(nil)]),
            mailing_postal_code <- one_of([string(:alphanumeric, min_length: 1, max_length: 10), constant(nil)]),
            mailing_country <- one_of([string(:alphanumeric, min_length: 1, max_length: 30), constant(nil)]) do
      %{
        "Id" => "test_#{:rand.uniform(10000)}",
        "FirstName" => first_name,
        "LastName" => last_name,
        "Email" => email,
        "Phone" => phone,
        "MobilePhone" => mobile_phone,
        "Title" => title,
        "MailingStreet" => nil,
        "MailingCity" => mailing_city,
        "MailingState" => mailing_state,
        "MailingPostalCode" => mailing_postal_code,
        "MailingCountry" => mailing_country
      }
    end
  end

  defp email_generator do
    gen all local <- string(:alphanumeric, min_length: 3, max_length: 10),
            domain <- string(:alphanumeric, min_length: 3, max_length: 8) do
      "#{local}@#{domain}.com"
    end
  end

  defp phone_generator do
    gen all digits <- string(?0..?9, length: 10) do
      "#{String.slice(digits, 0, 3)}-#{String.slice(digits, 3, 3)}-#{String.slice(digits, 6, 4)}"
    end
  end

  defp get_contact_value(contact, field) do
    Map.get(contact, field)
  end
end
