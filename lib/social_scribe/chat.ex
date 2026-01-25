defmodule SocialScribe.Chat do
  @moduledoc """
  The Chat context for managing AI-powered conversations about CRM contacts.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo

  alias SocialScribe.Chat.{ChatThread, ChatMessage, ChatMessageMention}

  # --- Thread Operations ---

  @doc """
  List all threads for a user, ordered by most recent activity.
  """
  def list_user_threads(user_id) do
    from(t in ChatThread,
      where: t.user_id == ^user_id,
      order_by: [desc: t.updated_at],
      preload: [chat_messages: ^last_message_query()]
    )
    |> Repo.all()
  end

  defp last_message_query do
    from(m in ChatMessage, order_by: [desc: m.inserted_at], limit: 1)
  end

  @doc """
  Get a single thread with all messages.
  Returns nil if not found or user doesn't own the thread.
  """
  def get_thread_with_messages(thread_id, user_id)
      when is_nil(thread_id) or is_nil(user_id),
      do: nil

  def get_thread_with_messages(thread_id, user_id) do
    from(t in ChatThread,
      where: t.id == ^thread_id and t.user_id == ^user_id,
      preload: [chat_messages: ^messages_with_mentions_query()]
    )
    |> Repo.one()
  end

  defp messages_with_mentions_query do
    from(m in ChatMessage, order_by: [asc: m.inserted_at], preload: [:mentions])
  end

  @doc """
  Get a thread by ID.
  """
  def get_thread!(id), do: Repo.get!(ChatThread, id)

  @doc """
  Get a thread by ID for a specific user.
  """
  def get_user_thread(thread_id, user_id) do
    Repo.get_by(ChatThread, id: thread_id, user_id: user_id)
  end

  @doc """
  Create a new chat thread.
  """
  def create_thread(attrs \\ %{}) do
    %ChatThread{}
    |> ChatThread.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a chat thread.
  """
  def update_thread(%ChatThread{} = thread, attrs) do
    thread
    |> ChatThread.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a chat thread.
  """
  def delete_thread(%ChatThread{} = thread) do
    Repo.delete(thread)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking thread changes.
  """
  def change_thread(%ChatThread{} = thread, attrs \\ %{}) do
    ChatThread.changeset(thread, attrs)
  end

  # --- Message Operations ---

  @doc """
  Create a message in a thread.
  """
  def create_message(attrs \\ %{}) do
    %ChatMessage{}
    |> ChatMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Create a user message with mentions.
  """
  def create_user_message(thread_id, content, mentions \\ []) do
    Repo.transaction(fn ->
      case create_message(%{
             chat_thread_id: thread_id,
             role: "user",
             content: content
           }) do
        {:ok, message} ->
          Enum.each(mentions, fn mention ->
            create_mention(Map.put(mention, :chat_message_id, message.id))
          end)

          # Touch the thread's updated_at
          thread = get_thread!(thread_id)
          update_thread(thread, %{})

          Repo.preload(message, :mentions)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Create an assistant message with sources.
  """
  def create_assistant_message(thread_id, content, sources \\ %{}) do
    result =
      create_message(%{
        chat_thread_id: thread_id,
        role: "assistant",
        content: content,
        sources: sources
      })

    # Touch the thread's updated_at
    case result do
      {:ok, message} ->
        thread = get_thread!(thread_id)
        update_thread(thread, %{})
        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Get all messages for a thread grouped by date.
  """
  def get_messages_grouped_by_date(thread_id) do
    ChatMessage
    |> where([m], m.chat_thread_id == ^thread_id)
    |> order_by([m], asc: m.inserted_at)
    |> preload(:mentions)
    |> Repo.all()
    |> Enum.group_by(fn msg -> Date.to_string(NaiveDateTime.to_date(msg.inserted_at)) end)
  end

  # --- Mention Operations ---

  @doc """
  Create a mention.
  """
  def create_mention(attrs \\ %{}) do
    %ChatMessageMention{}
    |> ChatMessageMention.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  List mentions for a message.
  """
  def list_message_mentions(message_id) do
    from(m in ChatMessageMention, where: m.chat_message_id == ^message_id)
    |> Repo.all()
  end
end
