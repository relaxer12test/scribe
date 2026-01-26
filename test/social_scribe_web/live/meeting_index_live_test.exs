defmodule SocialScribeWeb.MeetingIndexLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.MeetingsFixtures

  test "refresh loads meeting items after empty state", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, html} = live(conn, ~p"/dashboard/meetings")
    assert html =~ "No meetings yet"

    calendar_event = calendar_event_fixture(%{user_id: user.id})
    meeting = meeting_fixture(%{calendar_event_id: calendar_event.id})
    _participant = meeting_participant_fixture(%{meeting_id: meeting.id, name: "Pat Doe"})

    view
    |> element("button[phx-click='refresh']")
    |> render_click()

    html = render(view)
    assert html =~ meeting.title
    assert html =~ "View Details"
  end
end
