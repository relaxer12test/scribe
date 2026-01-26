defmodule SocialScribeWeb.ChatBubbleLiveTest do
  use SocialScribeWeb.ConnCase

  import Mox
  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures

  alias SocialScribe.Accounts
  alias SocialScribe.Chat

  setup :verify_on_exit!

  test "opens bubble and streams a response", %{conn: conn} do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    {:ok, view, html} =
      live_isolated(conn, SocialScribeWeb.ChatBubbleLive, session: %{"user_token" => token})

    refute html =~ "chat-panel"

    view
    |> element("button[phx-click='toggle_bubble']")
    |> render_click()

    assert has_element?(view, "#chat-panel")

    SocialScribe.AIContentGeneratorMock
    |> expect(:generate_chat_response_stream, fn query, contacts, meetings, crm_updates, history, callback ->
      assert query == "Hello bubble"
      assert contacts == []
      assert meetings == []
      assert crm_updates == []
      assert history == [%{role: "user", content: "Hello bubble"}]

      callback.("Hello ")
      callback.("from AI")

      {:ok, %{answer: "Hello from AI", sources: []}}
    end)

    view
    |> element("button[phx-click='send_message']")
    |> render_click(%{"content" => "Hello bubble"})

    :timer.sleep(200)

    html = render(view)
    assert html =~ "Hello bubble"
    assert html =~ "Hello from AI"

    [thread] = Chat.list_user_threads(user.id)
    assert String.starts_with?(thread.title, "Hello bubble")
  end
end
