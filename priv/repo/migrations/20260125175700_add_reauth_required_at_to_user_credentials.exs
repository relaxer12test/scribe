defmodule SocialScribe.Repo.Migrations.AddReauthRequiredAtToUserCredentials do
  use Ecto.Migration

  def change do
    alter table(:user_credentials) do
      add :reauth_required_at, :utc_datetime
    end
  end
end
