defmodule SocialScribe.Repo.Migrations.DropUserCredentialsProviderUidIndex do
  use Ecto.Migration

  def change do
    drop_if_exists(
      index(:user_credentials, [:provider, :uid], name: :user_credentials_provider_uid_index)
    )
  end
end
