defmodule SocialScribeWeb.HealthController do
  use SocialScribeWeb, :controller

  alias SocialScribe.Repo

  def index(conn, _params) do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} ->
        json(conn, %{status: "ok", db: "ok"})

      {:error, _error} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", db: "error"})
    end
  end
end
