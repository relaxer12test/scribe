defmodule SocialScribe.ChatAssistantTest do
  use SocialScribe.DataCase

  import Mox

  import SocialScribe.AccountsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.ChatFixtures
  import SocialScribe.CrmUpdatesFixtures
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
      transcript_data = [%{"speaker" => "Alex", "words" => [%{"text" => "Intro", "start_timestamp" => 1.0}]}]
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => transcript_data}})
      crm_contact_update_fixture(%{meeting_id: meeting.id, crm_provider: "hubspot", contact_id: "hs1"})

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn query, contacts, meetings, crm_updates, history ->
        assert query == "What did we discuss?"
        assert contacts == []
        assert Enum.any?(meetings, &(&1.id == meeting.id))
        assert Enum.any?(crm_updates, &(&1.meeting_id == meeting.id))
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
      |> expect(:generate_chat_response, fn _query, contacts, _meetings, _crm_updates, _history ->
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

    test "stores mention references only when they appear in the answer" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})

      mentions = [
        %{contact_id: "003", contact_name: "Pat Doe", crm_provider: "salesforce"},
        %{contact_id: "hs1", contact_name: "Alex Roe", crm_provider: "hubspot"}
      ]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, _contacts, _meetings, _crm_updates, _history ->
        {:ok, %{answer: "Pat Doe said hello.", sources: []}}
      end)

      assert {:ok, %{assistant_message: assistant_message}} =
               ChatAssistant.process_message(
                 thread.id,
                 user.id,
                 "Summarize",
                 mentions,
                 %{hubspot: nil, salesforce: nil}
               )

      assert length(assistant_message.mentions) == 1
      assert hd(assistant_message.mentions).contact_id == "003"
    end

    test "filters CRM updates to only mentioned contacts" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mention = %{contact_id: "003", contact_name: "Pat Doe", crm_provider: "salesforce"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn ^credential, "003" ->
        {:ok, %{id: "003", firstname: "Pat", lastname: "Doe", email: "pat@example.com"}}
      end)

      calendar_event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: calendar_event.id})
      meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => [%{"speaker" => "Pat", "words" => []}]}})

      _matching_update =
        crm_contact_update_fixture(%{
          meeting_id: meeting.id,
          crm_provider: "salesforce",
          contact_id: "003"
        })

      _other_update =
        crm_contact_update_fixture(%{
          meeting_id: meeting.id,
          crm_provider: "salesforce",
          contact_id: "999"
        })

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, _contacts, _meetings, crm_updates, _history ->
        assert Enum.any?(crm_updates, &(&1.contact_id == "003"))
        refute Enum.any?(crm_updates, &(&1.contact_id == "999"))
        {:ok, %{answer: "Found updates.", sources: []}}
      end)

      assert {:ok, _result} =
               ChatAssistant.process_message(
                 thread.id,
                 user.id,
                 "Any updates?",
                 [mention],
                 %{hubspot: nil, salesforce: credential}
               )
    end

    test "filters meetings to those mentioning the contact" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})
      credential = hubspot_credential_fixture(%{user_id: user.id})

      mention = %{contact_id: "hs1", contact_name: "Pat Doe", crm_provider: "hubspot"}

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn ^credential, "hs1" ->
        {:ok, %{id: "hs1", firstname: "Pat", lastname: "Doe", email: "pat@example.com"}}
      end)

      calendar_event_1 = calendar_event_fixture(%{user_id: user.id})
      meeting_1 = meeting_fixture(%{calendar_event_id: calendar_event_1.id})
      meeting_participant_fixture(%{meeting_id: meeting_1.id, name: "Pat Doe"})

      transcript_1 =
        %{"data" => [%{"speaker" => "Pat Doe", "words" => [%{"text" => "Update", "start_timestamp" => 2.0}]}]}

      meeting_transcript_fixture(%{meeting_id: meeting_1.id, content: transcript_1})

      calendar_event_2 = calendar_event_fixture(%{user_id: user.id})
      meeting_2 = meeting_fixture(%{calendar_event_id: calendar_event_2.id})
      meeting_participant_fixture(%{meeting_id: meeting_2.id, name: "Other Person"})

      transcript_2 =
        %{
          "data" => [%{"speaker" => "Other Person", "words" => [%{"text" => "Hello", "start_timestamp" => 3.0}]}]
        }

      meeting_transcript_fixture(%{meeting_id: meeting_2.id, content: transcript_2})

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, _contacts, meetings, _crm_updates, _history ->
        assert Enum.any?(meetings, &(&1.id == meeting_1.id))
        refute Enum.any?(meetings, &(&1.id == meeting_2.id))
        {:ok, %{answer: "Found meetings.", sources: []}}
      end)

      assert {:ok, _result} =
               ChatAssistant.process_message(
                 thread.id,
                 user.id,
                 "What did Pat say?",
                 [mention],
                 %{hubspot: credential, salesforce: nil}
               )
    end

    test "returns error when AI generation fails and keeps the user message" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, _contacts, _meetings, _crm_updates, _history ->
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

  describe "process_message_stream/6" do
    test "streams response chunks and persists messages" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})

      stream_callback = fn chunk -> send(self(), {:chunk, chunk}) end

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response_stream, fn query, contacts, meetings, crm_updates, history, callback ->
        assert query == "Hello"
        assert contacts == []
        assert meetings == []
        assert crm_updates == []
        assert history == [%{role: "user", content: "Hello"}]

        callback.("Hi ")
        callback.("there")

        {:ok, %{answer: "Hi there", sources: []}}
      end)

      assert {:ok, %{assistant_message: assistant_message}} =
               ChatAssistant.process_message_stream(
                 thread.id,
                 user.id,
                 "Hello",
                 [],
                 %{hubspot: nil, salesforce: nil},
                 stream_callback
               )

      assert_receive {:chunk, "Hi "}
      assert_receive {:chunk, "there"}

      assert assistant_message.content == "Hi there"

      thread = Chat.get_thread_with_messages(thread.id, user.id)
      assert length(thread.chat_messages) == 2
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
