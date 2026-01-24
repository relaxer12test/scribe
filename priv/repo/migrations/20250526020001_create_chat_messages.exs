defmodule SocialScribe.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages) do
      add :role, :string, null: false
      add :content, :text, null: false
      add :sources, :map, default: %{}
      add :chat_thread_id, references(:chat_threads, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_messages, [:chat_thread_id])
    create index(:chat_messages, [:inserted_at])
  end
end
