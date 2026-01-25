defmodule SocialScribeWeb.ChatLiveTest do
  use SocialScribeWeb.ConnCase

  import Mox
  import Phoenix.LiveViewTest

  import SocialScribe.AccountsFixtures

  alias SocialScribe.Chat

  setup :register_and_log_in_user
  setup :verify_on_exit!

  test "opens chat and shows welcome state", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/dashboard/chat")

    refute html =~ "chat-input"
    assert html =~ "Ask Anything"

    view
    |> element("button[phx-click='open_chat']")
    |> render_click()

    assert has_element?(view, "#chat-input")
    assert render(view) =~ "I can answer questions"
  end

  test "creates a thread and renders assistant response", %{conn: conn, user: user} do
    SocialScribe.AIContentGeneratorMock
    |> expect(:generate_chat_response, fn query, contacts, meetings, history ->
      assert query == "Hello there"
      assert contacts == []
      assert meetings == []
      assert history == []

      {:ok, %{answer: "Hi!", sources: []}}
    end)

    {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

    view
    |> element("button[phx-click='open_chat']")
    |> render_click()

    view
    |> element("#chat-input")
    |> render_keyup(%{"value" => "Hello there"})

    view
    |> element("button[phx-click='send_message']")
    |> render_click()

    :timer.sleep(100)

    html = render(view)
    assert html =~ "Hello there"
    assert html =~ "Hi!"

    [thread] = Chat.list_user_threads(user.id)
    assert String.starts_with?(thread.title, "Hello")
  end

  test "shows mention dropdown results when typing @ query", %{conn: conn, user: user} do
    _hubspot_credential = hubspot_credential_fixture(%{user_id: user.id})

    SocialScribe.HubspotApiMock
    |> expect(:search_contacts, fn _credential, "Jo" ->
      {:ok, [%{id: "hs1", firstname: "John", lastname: "Doe", email: "john@example.com"}]}
    end)

    {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

    view
    |> element("button[phx-click='open_chat']")
    |> render_click()

    view
    |> element("#chat-input")
    |> render_keyup(%{"value" => "Hi @Jo"})

    :timer.sleep(100)

    html = render(view)
    assert html =~ "John Doe"
    assert html =~ "john@example.com"
  end
end
