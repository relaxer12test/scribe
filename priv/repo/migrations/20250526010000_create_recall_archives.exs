defmodule SocialScribe.Repo.Migrations.CreateRecallArchives do
  use Ecto.Migration

  def change do
    create table(:recall_archives) do
      add :recall_bot_id, :string, null: false
      add :meeting_url, :string
      add :status, :string
      add :title, :string
      add :recorded_at, :utc_datetime
      add :duration_seconds, :integer
      add :transcript, :map
      add :participants, :map
      add :bot_metadata, :map
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:recall_archives, [:user_id])
    create index(:recall_archives, [:meeting_url])
    create unique_index(:recall_archives, [:user_id, :recall_bot_id])
  end
end
