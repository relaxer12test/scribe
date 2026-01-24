defmodule SocialScribeWeb.RecallArchiveLive.Index do
  use SocialScribeWeb, :live_view

  alias SocialScribe.RecallArchives

  @impl true
  def mount(_params, _session, socket) do
    archives = RecallArchives.list_user_archives(socket.assigns.current_user)

    socket =
      socket
      |> assign(:page_title, "Recall Archive")
      |> assign(:archives, archives)

    {:ok, socket}
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    "#{minutes} min"
  end
end
