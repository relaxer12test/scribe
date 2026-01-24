defmodule SocialScribe.Repo.Migrations.CreateChatMessageMentions do
  use Ecto.Migration

  def change do
    create table(:chat_message_mentions) do
      add :contact_id, :string, null: false
      add :contact_name, :string, null: false
      add :crm_provider, :string, null: false
      add :chat_message_id, references(:chat_messages, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_message_mentions, [:chat_message_id])
    create index(:chat_message_mentions, [:contact_id, :crm_provider])
  end
end
