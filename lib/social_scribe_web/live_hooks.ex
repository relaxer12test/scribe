defmodule SocialScribeWeb.LiveHooks do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:assign_current_path, _params, session, socket) do
    socket =
      socket
      |> attach_hook(:assign_current_path, :handle_params, &assign_current_path/3)
      |> assign(:user_token, session["user_token"])

    {:cont, socket}
  end

  defp assign_current_path(_params, uri, socket) do
    uri = URI.parse(uri)

    {:cont, assign(socket, :current_path, uri.path)}
  end
end
