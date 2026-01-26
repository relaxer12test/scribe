defmodule SocialScribeWeb.LegalControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  test "renders privacy policy page", %{conn: conn} do
    conn = get(conn, ~p"/privacy")
    assert html_response(conn, 200) =~ "Privacy Policy"
  end

  test "renders terms of service page", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms of Service"
  end

  test "renders data deletion page", %{conn: conn} do
    conn = get(conn, ~p"/delete")
    html = html_response(conn, 200)
    assert html =~ "Data Deletion Instructions"
    assert html =~ "mailto:"
  end
end
