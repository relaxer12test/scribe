defmodule SocialScribe.Chat.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Chat.{ChatThread, ChatMessageMention}

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    field :sources, :map, default: %{}

    belongs_to :chat_thread, ChatThread
    has_many :mentions, ChatMessageMention

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :sources, :chat_thread_id])
    |> validate_required([:role, :content, :chat_thread_id])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
