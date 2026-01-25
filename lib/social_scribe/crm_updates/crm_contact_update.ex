defmodule SocialScribe.CrmUpdates.CrmContactUpdate do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Meetings.Meeting

  schema "crm_contact_updates" do
    field :crm_provider, :string
    field :contact_id, :string
    field :contact_name, :string
    field :updates, :map
    field :status, :string, default: "applied"
    field :applied_at, :utc_datetime

    belongs_to :meeting, Meeting

    timestamps(type: :utc_datetime)
  end

  def changeset(update, attrs) do
    update
    |> cast(attrs, [
      :crm_provider,
      :contact_id,
      :contact_name,
      :updates,
      :status,
      :applied_at,
      :meeting_id
    ])
    |> validate_required([:crm_provider, :contact_id, :updates, :applied_at, :meeting_id])
    |> validate_inclusion(:crm_provider, ["hubspot", "salesforce"])
    |> validate_inclusion(:status, ["applied"])
  end
end
