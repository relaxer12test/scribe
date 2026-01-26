defmodule SocialScribeWeb.HealthControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  test "GET /health returns ok when db is reachable", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/health")

    assert %{"status" => "ok", "db" => "ok", "git_commit" => _} = json_response(conn, 200)
  end
end
