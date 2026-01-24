defmodule SocialScribe.Repo.Migrations.CreateChatThreads do
  use Ecto.Migration

  def change do
    create table(:chat_threads) do
      add :title, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_threads, [:user_id])
    create index(:chat_threads, [:inserted_at])
  end
end
