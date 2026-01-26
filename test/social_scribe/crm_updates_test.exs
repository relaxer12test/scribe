defmodule SocialScribe.CrmUpdatesTest do
  use SocialScribe.DataCase

  alias SocialScribe.CrmUpdates
  alias SocialScribe.CrmUpdates.CrmContactUpdate

  import SocialScribe.MeetingsFixtures

  describe "create_contact_update/1" do
    test "creates a CRM update with valid attributes" do
      meeting = meeting_fixture()
      applied_at = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        meeting_id: meeting.id,
        crm_provider: "salesforce",
        contact_id: "003",
        contact_name: "Pat Doe",
        updates: %{"Phone" => "555-0100"},
        status: "applied",
        applied_at: applied_at
      }

      assert {:ok, %CrmContactUpdate{} = update} = CrmUpdates.create_contact_update(attrs)
      assert update.meeting_id == meeting.id
      assert update.contact_id == "003"
      assert update.status == "applied"
      assert update.applied_at == applied_at
    end

    test "validates required fields" do
      assert {:error, changeset} = CrmUpdates.create_contact_update(%{})

      assert "can't be blank" in errors_on(changeset).crm_provider
      assert "can't be blank" in errors_on(changeset).contact_id
      assert "can't be blank" in errors_on(changeset).updates
      assert "can't be blank" in errors_on(changeset).applied_at
      assert "can't be blank" in errors_on(changeset).meeting_id
    end

    test "rejects invalid provider and status" do
      meeting = meeting_fixture()

      attrs = %{
        meeting_id: meeting.id,
        crm_provider: "other",
        contact_id: "003",
        updates: %{"Phone" => "555-0100"},
        status: "pending",
        applied_at: DateTime.utc_now()
      }

      assert {:error, changeset} = CrmUpdates.create_contact_update(attrs)
      assert "is invalid" in errors_on(changeset).crm_provider
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "list_updates_for_meetings/1" do
    test "returns empty list for empty meeting ids" do
      assert CrmUpdates.list_updates_for_meetings([]) == []
    end

    test "returns updates for meeting ids ordered by applied_at desc" do
      meeting = meeting_fixture()
      other_meeting = meeting_fixture()
      ignored_meeting = meeting_fixture()

      older = DateTime.add(DateTime.utc_now(), -3600, :second)
      newer = DateTime.utc_now()

      {:ok, older_update} =
        CrmUpdates.create_contact_update(%{
          meeting_id: meeting.id,
          crm_provider: "hubspot",
          contact_id: "hs-1",
          contact_name: "Older",
          updates: %{"email" => "older@example.com"},
          status: "applied",
          applied_at: older
        })

      {:ok, newer_update} =
        CrmUpdates.create_contact_update(%{
          meeting_id: other_meeting.id,
          crm_provider: "salesforce",
          contact_id: "sf-1",
          contact_name: "Newer",
          updates: %{"Phone" => "555-0101"},
          status: "applied",
          applied_at: newer
        })

      {:ok, _ignored_update} =
        CrmUpdates.create_contact_update(%{
          meeting_id: ignored_meeting.id,
          crm_provider: "salesforce",
          contact_id: "sf-ignored",
          contact_name: "Ignored",
          updates: %{"Phone" => "555-0999"},
          status: "applied",
          applied_at: newer
        })

      updates = CrmUpdates.list_updates_for_meetings([meeting.id, other_meeting.id])

      assert Enum.map(updates, & &1.id) == [newer_update.id, older_update.id]
      assert Enum.all?(updates, &(&1.meeting != nil))
    end
  end
end
