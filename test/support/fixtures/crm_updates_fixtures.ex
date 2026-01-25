defmodule SocialScribe.CrmUpdatesFixtures do
  @moduledoc """
  Test helpers for creating CRM update records.
  """

  import SocialScribe.MeetingsFixtures

  def crm_contact_update_fixture(attrs \\ %{}) do
    meeting_id = attrs[:meeting_id] || meeting_fixture().id

    {:ok, update} =
      attrs
      |> Enum.into(%{
        meeting_id: meeting_id,
        crm_provider: "salesforce",
        contact_id: "003",
        contact_name: "Pat Doe",
        updates: %{"Phone" => "555-0100"},
        status: "applied",
        applied_at: DateTime.utc_now()
      })
      |> SocialScribe.CrmUpdates.create_contact_update()

    update
  end
end
