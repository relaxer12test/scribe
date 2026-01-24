defmodule SocialScribe.Chat.ChatThread do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.Chat.ChatMessage

  schema "chat_threads" do
    field :title, :string

    belongs_to :user, User
    has_many :chat_messages, ChatMessage

    timestamps()
  end

  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:title, :user_id])
    |> validate_required([:user_id])
  end
end
