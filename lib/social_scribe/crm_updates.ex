defmodule SocialScribe.CrmUpdates do
  @moduledoc """
  The CrmUpdates context.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo
  alias SocialScribe.CrmUpdates.CrmContactUpdate

  def create_contact_update(attrs \\ %{}) do
    %CrmContactUpdate{}
    |> CrmContactUpdate.changeset(attrs)
    |> Repo.insert()
  end

  def list_updates_for_meetings([]), do: []

  def list_updates_for_meetings(meeting_ids) when is_list(meeting_ids) do
    from(u in CrmContactUpdate,
      where: u.meeting_id in ^meeting_ids,
      order_by: [desc: u.applied_at, desc: u.inserted_at],
      preload: [:meeting]
    )
    |> Repo.all()
  end
end
