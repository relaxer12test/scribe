defmodule SocialScribe.ChatAssistantTest do
  use SocialScribe.DataCase

  import Mox

  import SocialScribe.AccountsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.ChatFixtures
  import SocialScribe.MeetingsFixtures

  alias SocialScribe.Chat
  alias SocialScribe.ChatAssistant

  setup :verify_on_exit!

  describe "process_message/5" do
    test "creates user and assistant messages with meeting context" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})

      calendar_event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: calendar_event.id})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => []}})

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn query, contacts, meetings, history ->
        assert query == "What did we discuss?"
        assert contacts == []
        assert Enum.any?(meetings, &(&1.id == meeting.id))
        assert history == [%{role: "user", content: "What did we discuss?"}]

        {:ok,
         %{
           answer: "We discussed the roadmap.",
           sources: [%{"meeting_id" => meeting.id, "title" => meeting.title, "timestamp" => "00:01"}]
         }}
      end)

      assert {:ok, %{user_message: user_message, assistant_message: assistant_message}} =
               ChatAssistant.process_message(
                 thread.id,
                 user.id,
                 "What did we discuss?",
                 [],
                 %{hubspot: nil, salesforce: nil}
               )

      assert user_message.role == "user"
      assert assistant_message.role == "assistant"
      assert length(assistant_message.sources["meetings"]) == 1
    end

    test "includes mentioned salesforce contact in AI context" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mention = %{contact_id: "003", contact_name: "Pat Doe", crm_provider: "salesforce"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn ^credential, "003" ->
        {:ok, %{id: "003", firstname: "Pat", lastname: "Doe", email: "pat@example.com"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, contacts, _meetings, _history ->
        assert Enum.any?(contacts, &(&1.id == "003" && &1.crm_provider == "salesforce"))
        {:ok, %{answer: "Pat is VP.", sources: []}}
      end)

      assert {:ok, _result} =
               ChatAssistant.process_message(
                 thread.id,
                 user.id,
                 "Who is Pat?",
                 [mention],
                 %{hubspot: nil, salesforce: credential}
               )
    end

    test "returns error when AI generation fails and keeps the user message" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, _contacts, _meetings, _history ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               ChatAssistant.process_message(
                 thread.id,
                 user.id,
                 "Hello",
                 [],
                 %{hubspot: nil, salesforce: nil}
               )

      thread = Chat.get_thread_with_messages(thread.id, user.id)
      assert length(thread.chat_messages) == 1
      assert hd(thread.chat_messages).role == "user"
    end

    test "returns reauth_required when Salesforce contact lookup fails" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mention = %{contact_id: "003", contact_name: "Pat Doe", crm_provider: "salesforce"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn ^credential, "003" ->
        {:error, {:reauth_required, %{id: credential.id}}}
      end)

      assert {:error, {:reauth_required, _info}} =
               ChatAssistant.process_message(
                 thread.id,
                 user.id,
                 "Who is Pat?",
                 [mention],
                 %{hubspot: nil, salesforce: credential}
               )
    end
  end

  describe "search_contacts/2" do
    test "combines hubspot and salesforce results with tags" do
      user = user_fixture()
      hubspot = hubspot_credential_fixture(%{user_id: user.id})
      salesforce = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn ^hubspot, "Jane" ->
        {:ok, [%{id: "hs1", firstname: "Jane", lastname: "Hub", email: "jane@hub.com"}]}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn ^salesforce, "Jane" ->
        {:ok, [%{id: "sf1", firstname: "Jane", lastname: "Force", email: "jane@sf.com"}]}
      end)

      assert {:ok, results, errors} =
               ChatAssistant.search_contacts("Jane", %{hubspot: hubspot, salesforce: salesforce})

      assert Enum.any?(results, &(&1.id == "hs1" && &1.crm_provider == "hubspot"))
      assert Enum.any?(results, &(&1.id == "sf1" && &1.crm_provider == "salesforce"))
      assert errors.hubspot == nil
      assert errors.salesforce == nil
    end
  end
end
