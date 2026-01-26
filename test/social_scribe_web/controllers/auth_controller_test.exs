defmodule SocialScribeWeb.AuthControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  alias SocialScribe.Accounts
  alias SocialScribeWeb.AuthController

  @describetag :capture_log

  setup :register_and_log_in_user

  test "salesforce callback stores credential and redirects", %{conn: conn, user: user} do
    auth = salesforce_auth("valid-token")

    conn =
      conn
      |> fetch_flash()
      |> assign(:ueberauth_auth, auth)
      |> assign(:current_user, user)

    conn = AuthController.callback(conn, %{"provider" => "salesforce"})

    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
             "Salesforce account connected successfully!"
    assert redirected_to(conn) == ~p"/dashboard/settings"

    credential = Accounts.get_user_credential(user, "salesforce", auth.uid)
    assert credential
    assert credential.email == auth.info.email
  end

  test "salesforce callback redirects to stored return_to", %{conn: conn, user: user} do
    auth = salesforce_auth("valid-token")
    return_to = "/dashboard/meetings/123"

    conn =
      conn
      |> init_test_session(%{salesforce_return_to: return_to})
      |> fetch_flash()
      |> assign(:ueberauth_auth, auth)
      |> assign(:current_user, user)

    conn = AuthController.callback(conn, %{"provider" => "salesforce"})

    assert redirected_to(conn) == return_to
  end

  test "salesforce callback shows error when credential is invalid", %{conn: conn, user: user} do
    auth = salesforce_auth(nil)

    conn =
      conn
      |> fetch_flash()
      |> assign(:ueberauth_auth, auth)
      |> assign(:current_user, user)

    conn = AuthController.callback(conn, %{"provider" => "salesforce"})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
             "Could not connect Salesforce account."
    assert redirected_to(conn) == ~p"/dashboard/settings"

    refute Accounts.get_user_credential(user, "salesforce", auth.uid)
  end

  defp salesforce_auth(token) do
    %Ueberauth.Auth{
      provider: :salesforce,
      uid: "salesforce-uid-123",
      info: %Ueberauth.Auth.Info{
        email: "salesforce@example.com",
        name: "Salesforce User"
      },
      credentials: %Ueberauth.Auth.Credentials{
        token: token,
        refresh_token: "refresh-token",
        expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
      }
    }
  end
end
