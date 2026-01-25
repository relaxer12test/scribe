defmodule SocialScribe.Repo.Migrations.CreateCrmContactUpdates do
  use Ecto.Migration

  def change do
    create table(:crm_contact_updates) do
      add :crm_provider, :string, null: false
      add :contact_id, :string, null: false
      add :contact_name, :string
      add :updates, :map, null: false
      add :status, :string, null: false, default: "applied"
      add :applied_at, :utc_datetime, null: false
      add :meeting_id, references(:meetings, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:crm_contact_updates, [:meeting_id])
    create index(:crm_contact_updates, [:crm_provider, :contact_id])
  end
end
