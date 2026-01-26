defmodule SocialScribeWeb.MeetingShowLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.MeetingsFixtures

  test "renders transcript speaker from participant metadata", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    calendar_event = calendar_event_fixture(%{user_id: user.id})
    meeting = meeting_fixture(%{calendar_event_id: calendar_event.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "participant" => %{"name" => "Pat Doe"},
            "words" => [%{"text" => "Hello there", "start_timestamp" => 1.0}]
          }
        ]
      }
    })

    {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

    assert html =~ "Pat Doe:"
    assert html =~ "Hello there"
  end
end
