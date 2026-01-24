defmodule SocialScribe.RecallArchives.RecallArchive do
  use Ecto.Schema
  import Ecto.Changeset

  schema "recall_archives" do
    field :recall_bot_id, :string
    field :meeting_url, :string
    field :status, :string
    field :title, :string
    field :recorded_at, :utc_datetime
    field :duration_seconds, :integer
    field :transcript, :map
    field :participants, :map
    field :bot_metadata, :map

    belongs_to :user, SocialScribe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(recall_archive, attrs) do
    recall_archive
    |> cast(attrs, [
      :recall_bot_id,
      :meeting_url,
      :status,
      :title,
      :recorded_at,
      :duration_seconds,
      :transcript,
      :participants,
      :bot_metadata,
      :user_id
    ])
    |> validate_required([:recall_bot_id, :user_id])
    |> unique_constraint([:user_id, :recall_bot_id])
  end
end
