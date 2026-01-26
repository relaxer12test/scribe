defmodule SocialScribeWeb.HealthController do
  use SocialScribeWeb, :controller

  alias SocialScribe.Repo

  def index(conn, _params) do
    git_commit = Application.get_env(:social_scribe, :git_commit, "unknown")

    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} ->
        json(conn, %{status: "ok", db: "ok", git_commit: git_commit})

      {:error, _error} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", db: "error", git_commit: git_commit})
    end
  end
end
