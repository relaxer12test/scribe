defmodule SocialScribe.ChatFixtures do
  @moduledoc """
  Test helpers for creating chat entities.
  """

  import SocialScribe.AccountsFixtures

  alias SocialScribe.Chat

  @doc """
  Generate a chat_thread.
  """
  def chat_thread_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || user_fixture().id

    {:ok, thread} =
      attrs
      |> Enum.into(%{
        user_id: user_id,
        title: "Test Chat Thread #{System.unique_integer([:positive])}"
      })
      |> Chat.create_thread()

    thread
  end

  @doc """
  Generate a chat_message.
  """
  def chat_message_fixture(attrs \\ %{}) do
    chat_thread_id = attrs[:chat_thread_id] || chat_thread_fixture().id

    {:ok, message} =
      attrs
      |> Enum.into(%{
        chat_thread_id: chat_thread_id,
        role: attrs[:role] || "user",
        content: "Test message content #{System.unique_integer([:positive])}",
        sources: %{}
      })
      |> Chat.create_message()

    message
  end

  @doc """
  Generate a chat_message_mention.
  """
  def chat_message_mention_fixture(attrs \\ %{}) do
    chat_message_id = attrs[:chat_message_id] || chat_message_fixture().id

    {:ok, mention} =
      attrs
      |> Enum.into(%{
        chat_message_id: chat_message_id,
        contact_id: "contact_#{System.unique_integer([:positive])}",
        contact_name: "John Doe",
        crm_provider: "hubspot"
      })
      |> Chat.create_mention()

    mention
  end
end
