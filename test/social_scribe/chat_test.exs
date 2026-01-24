defmodule SocialScribe.ChatTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat

  import SocialScribe.AccountsFixtures
  import SocialScribe.ChatFixtures

  describe "chat_threads" do
    alias SocialScribe.Chat.ChatThread

    test "list_user_threads/1 returns threads for user" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})

      threads = Chat.list_user_threads(user.id)
      assert length(threads) == 1
      assert hd(threads).id == thread.id
    end

    test "list_user_threads/1 does not return other users' threads" do
      user1 = user_fixture()
      user2 = user_fixture()
      _thread1 = chat_thread_fixture(%{user_id: user1.id})
      thread2 = chat_thread_fixture(%{user_id: user2.id})

      threads = Chat.list_user_threads(user2.id)
      assert length(threads) == 1
      assert hd(threads).id == thread2.id
    end

    test "get_thread_with_messages/2 returns thread with messages for owner" do
      user = user_fixture()
      thread = chat_thread_fixture(%{user_id: user.id})
      _message = chat_message_fixture(%{chat_thread_id: thread.id, content: "Hello"})

      result = Chat.get_thread_with_messages(thread.id, user.id)
      assert result.id == thread.id
      assert length(result.chat_messages) == 1
    end

    test "get_thread_with_messages/2 returns nil for non-owner" do
      user1 = user_fixture()
      user2 = user_fixture()
      thread = chat_thread_fixture(%{user_id: user1.id})

      result = Chat.get_thread_with_messages(thread.id, user2.id)
      assert is_nil(result)
    end

    test "create_thread/1 creates a thread" do
      user = user_fixture()

      assert {:ok, %ChatThread{} = thread} = Chat.create_thread(%{user_id: user.id})
      assert thread.user_id == user.id
    end

    test "create_thread/1 with title creates a titled thread" do
      user = user_fixture()

      assert {:ok, %ChatThread{} = thread} =
               Chat.create_thread(%{user_id: user.id, title: "My Chat"})

      assert thread.title == "My Chat"
    end

    test "update_thread/2 updates a thread" do
      thread = chat_thread_fixture()

      assert {:ok, %ChatThread{} = updated} = Chat.update_thread(thread, %{title: "New Title"})
      assert updated.title == "New Title"
    end

    test "delete_thread/1 deletes a thread" do
      thread = chat_thread_fixture()

      assert {:ok, %ChatThread{}} = Chat.delete_thread(thread)
      assert_raise Ecto.NoResultsError, fn -> Chat.get_thread!(thread.id) end
    end
  end

  describe "chat_messages" do
    alias SocialScribe.Chat.ChatMessage

    test "create_message/1 creates a user message" do
      thread = chat_thread_fixture()

      assert {:ok, %ChatMessage{} = message} =
               Chat.create_message(%{
                 chat_thread_id: thread.id,
                 role: "user",
                 content: "Hello"
               })

      assert message.role == "user"
      assert message.content == "Hello"
    end

    test "create_message/1 creates an assistant message with sources" do
      thread = chat_thread_fixture()
      sources = %{"meetings" => [%{"meeting_id" => 1, "title" => "Test Meeting"}]}

      assert {:ok, %ChatMessage{} = message} =
               Chat.create_message(%{
                 chat_thread_id: thread.id,
                 role: "assistant",
                 content: "Here's what I found",
                 sources: sources
               })

      assert message.role == "assistant"
      assert message.sources == sources
    end

    test "create_user_message/3 creates message with mentions" do
      thread = chat_thread_fixture()

      mentions = [
        %{
          contact_id: "123",
          contact_name: "John Doe",
          crm_provider: "hubspot"
        }
      ]

      assert {:ok, message} = Chat.create_user_message(thread.id, "Hello @John", mentions)
      assert message.role == "user"
      assert message.content == "Hello @John"
      assert length(message.mentions) == 1
      assert hd(message.mentions).contact_name == "John Doe"
    end

    test "create_assistant_message/3 creates assistant message" do
      thread = chat_thread_fixture()
      sources = %{"meetings" => [%{"meeting_id" => 1, "title" => "Test"}]}

      assert {:ok, message} = Chat.create_assistant_message(thread.id, "Response", sources)
      assert message.role == "assistant"
      assert message.sources == sources
    end

    test "get_messages_grouped_by_date/1 returns messages grouped by date" do
      thread = chat_thread_fixture()
      _message1 = chat_message_fixture(%{chat_thread_id: thread.id})
      _message2 = chat_message_fixture(%{chat_thread_id: thread.id})

      grouped = Chat.get_messages_grouped_by_date(thread.id)
      assert is_map(grouped)
      # All messages created today should be in today's group
      today = Date.to_string(Date.utc_today())
      assert Map.has_key?(grouped, today)
      assert length(grouped[today]) == 2
    end
  end

  describe "chat_message_mentions" do
    alias SocialScribe.Chat.ChatMessageMention

    test "create_mention/1 creates a mention" do
      message = chat_message_fixture()

      assert {:ok, %ChatMessageMention{} = mention} =
               Chat.create_mention(%{
                 chat_message_id: message.id,
                 contact_id: "123",
                 contact_name: "Jane Doe",
                 crm_provider: "salesforce"
               })

      assert mention.contact_name == "Jane Doe"
      assert mention.crm_provider == "salesforce"
    end

    test "list_message_mentions/1 returns mentions for message" do
      message = chat_message_fixture()
      _mention = chat_message_mention_fixture(%{chat_message_id: message.id})

      mentions = Chat.list_message_mentions(message.id)
      assert length(mentions) == 1
    end
  end
end
