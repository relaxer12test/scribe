defmodule SocialScribeWeb.SalesforceModalMoxTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import Mox

  setup :verify_on_exit!

  describe "Salesforce Modal with mocked API" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "search_contacts returns mocked results", %{conn: conn, meeting: meeting} do
      mock_contacts = [
        %{
          id: "003000000000001",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: nil,
          display_name: "John Doe"
        },
        %{
          id: "003000000000002",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@example.com",
          phone: "555-1234",
          display_name: "Jane Smith"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "John"
        {:ok, mock_contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/crm/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      html = render(view)

      assert html =~ "John Doe"
      assert html =~ "Jane Smith"
    end

    test "search_contacts handles API error gracefully", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:error, {:api_error, 500, %{"message" => "Internal server error"}}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/crm/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test"})

      :timer.sleep(200)

      html = render(view)

      assert html =~ "Failed to search contacts"
    end

    test "selecting contact triggers suggestion generation", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "003000000000001",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        display_name: "John Doe"
      }

      mock_salesforce_contact = %{
        "Phone" => nil,
        "FirstName" => "John",
        "LastName" => "Doe",
        "Email" => "john@example.com",
        :id => "003000000000001",
        :firstname => "John",
        :lastname => "Doe",
        :email => "john@example.com"
      }

      mock_suggestions = [
        %{
          field: "Phone",
          value: "555-1234",
          context: "Mentioned phone number",
          timestamp: "00:10"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [mock_contact]}
      end)
      |> expect(:get_contact, fn _credential, contact_id ->
        assert contact_id == "003000000000001"
        {:ok, mock_salesforce_contact}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, mock_suggestions}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/crm/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='003000000000001']")
      |> render_click()

      :timer.sleep(500)

      assert has_element?(view, "#salesforce-modal-wrapper")
      assert render(view) =~ "555-1234"
    end

    test "contact dropdown shows search results", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "003000000000003",
        firstname: "Test",
        lastname: "User",
        email: "test@example.com",
        phone: nil,
        display_name: "Test User"
      }

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [mock_contact]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/crm/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test"})

      :timer.sleep(200)

      html = render(view)

      assert html =~ "Test User"
      assert html =~ "test@example.com"
    end

    test "applies selected updates and closes modal", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "003000000000001",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        display_name: "John Doe"
      }

      mock_salesforce_contact = %{
        "Phone" => nil,
        "FirstName" => "John",
        "LastName" => "Doe",
        "Email" => "john@example.com",
        :id => "003000000000001",
        :firstname => "John",
        :lastname => "Doe",
        :email => "john@example.com"
      }

      mock_suggestions = [
        %{
          field: "Phone",
          value: "555-1234",
          context: "Mentioned phone number",
          timestamp: "00:10"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [mock_contact]}
      end)
      |> expect(:get_contact, fn _credential, contact_id ->
        assert contact_id == "003000000000001"
        {:ok, mock_salesforce_contact}
      end)
      |> expect(:update_contact, fn _credential, contact_id, updates ->
        assert contact_id == "003000000000001"
        assert updates == %{"Phone" => "555-1234"}
        {:ok, %{id: contact_id}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, mock_suggestions}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/crm/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='003000000000001']")
      |> render_click()

      :timer.sleep(500)

      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{"apply" => %{"Phone" => "1"}, "values" => %{"Phone" => "555-1234"}})

      assert_patch(view, ~p"/dashboard/meetings/#{meeting.id}")
      assert render(view) =~ "Successfully updated"
    end

    test "shows error when update fails", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "003000000000002",
        firstname: "Jane",
        lastname: "Doe",
        email: "jane@example.com",
        phone: nil,
        display_name: "Jane Doe"
      }

      mock_salesforce_contact = %{
        "Phone" => nil,
        "FirstName" => "Jane",
        "LastName" => "Doe",
        "Email" => "jane@example.com",
        :id => "003000000000002",
        :firstname => "Jane",
        :lastname => "Doe",
        :email => "jane@example.com"
      }

      mock_suggestions = [
        %{
          field: "Phone",
          value: "777-8888",
          context: "Mentioned phone number",
          timestamp: "00:15"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [mock_contact]}
      end)
      |> expect(:get_contact, fn _credential, contact_id ->
        assert contact_id == "003000000000002"
        {:ok, mock_salesforce_contact}
      end)
      |> expect(:update_contact, fn _credential, contact_id, _updates ->
        assert contact_id == "003000000000002"
        {:error, :update_failed}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, mock_suggestions}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/crm/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jane"})

      :timer.sleep(200)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='003000000000002']")
      |> render_click()

      :timer.sleep(500)

      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{"apply" => %{"Phone" => "1"}, "values" => %{"Phone" => "777-8888"}})

      assert render(view) =~ "Failed to update contact"
    end
  end

  describe "Salesforce API behavior delegation" do
    setup do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      %{credential: credential}
    end

    test "search_contacts delegates to implementation", %{credential: credential} do
      expected = [%{id: "1", firstname: "Test", lastname: "User"}]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, query ->
        assert query == "test query"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.search_contacts(credential, "test query")
    end

    test "get_contact delegates to implementation", %{credential: credential} do
      expected = %{id: "003000000000001", firstname: "John", lastname: "Doe"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "003000000000001"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.get_contact(credential, "003000000000001")
    end

    test "update_contact delegates to implementation", %{credential: credential} do
      updates = %{"Phone" => "555-1234", "Email" => "test@example.com"}
      expected = %{"Phone" => "555-1234", :id => "003000000000001"}

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _cred, contact_id, upd ->
        assert contact_id == "003000000000001"
        assert upd == updates
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.update_contact(
                 credential,
                 "003000000000001",
                 updates
               )
    end

    test "apply_updates delegates to implementation", %{credential: credential} do
      updates_list = [
        %{field: "Phone", new_value: "555-1234", apply: true},
        %{field: "Email", new_value: "test@example.com", apply: false}
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:apply_updates, fn _cred, contact_id, list ->
        assert contact_id == "003000000000001"
        assert list == updates_list
        {:ok, %{id: "003000000000001"}}
      end)

      assert {:ok, _} =
               SocialScribe.SalesforceApiBehaviour.apply_updates(
                 credential,
                 "003000000000001",
                 updates_list
               )
    end
  end

  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "John Doe",
            "words" => [
              %{"text" => "Hello,"},
              %{"text" => "my"},
              %{"text" => "phone"},
              %{"text" => "is"},
              %{"text" => "555-1234"}
            ]
          }
        ]
      }
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
