defmodule SocialScribe.Chat.ChatMessageMention do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Chat.ChatMessage

  schema "chat_message_mentions" do
    field :contact_id, :string
    field :contact_name, :string
    field :crm_provider, :string

    belongs_to :chat_message, ChatMessage

    timestamps()
  end

  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:contact_id, :contact_name, :crm_provider, :chat_message_id])
    |> validate_required([:contact_id, :contact_name, :crm_provider, :chat_message_id])
    |> validate_inclusion(:crm_provider, ["hubspot", "salesforce"])
  end
end
