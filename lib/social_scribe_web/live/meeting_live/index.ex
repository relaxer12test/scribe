defmodule SocialScribeWeb.MeetingLive.Index do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo

  alias SocialScribe.Bots
  alias SocialScribe.Meetings

  @impl true
  def mount(_params, _session, socket) do
    meeting_items = Meetings.list_user_meeting_items(socket.assigns.current_user)

    socket =
      socket
      |> assign(:page_title, "Meetings")
      |> assign(:meeting_items, meeting_items)

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh_bot", %{"id" => bot_id}, socket) do
    socket =
      case Integer.parse(bot_id) do
        {parsed_id, ""} ->
          case Bots.refresh_bot_and_meeting(socket.assigns.current_user, parsed_id) do
            {:ok, :meeting_created} ->
              put_flash(socket, :info, "Meeting imported. Transcript will appear once ready.")

            {:ok, :pending} ->
              put_flash(socket, :info, "Transcript not ready yet. Try again soon.")

            {:ok, :already_processed} ->
              put_flash(socket, :info, "Meeting is already processed.")

            {:error, :not_found} ->
              put_flash(socket, :error, "Meeting bot not found.")

            {:error, _reason} ->
              put_flash(socket, :error, "Failed to refresh meeting. Please try again.")
          end

        _ ->
          put_flash(socket, :error, "Invalid meeting bot id.")
      end

    meeting_items = Meetings.list_user_meeting_items(socket.assigns.current_user)

    {:noreply, assign(socket, :meeting_items, meeting_items)}
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    "#{minutes} min"
  end

  defp format_status(nil), do: "Unknown"

  defp format_status(status) when is_binary(status) do
    status
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp status_badge_class(nil), do: "bg-slate-100 text-slate-600"

  defp status_badge_class(status) when is_binary(status) do
    normalized = String.downcase(status)

    cond do
      String.contains?(normalized, "error") -> "bg-rose-100 text-rose-700"
      normalized == "done" -> "bg-emerald-100 text-emerald-700"
      normalized in ["ready", "recording", "processing", "joining_call", "waiting"] ->
        "bg-amber-100 text-amber-700"
      true -> "bg-slate-100 text-slate-700"
    end
  end

  defp status_badge_class(_status), do: "bg-slate-100 text-slate-700"

  defp meeting_title(bot) do
    cond do
      bot.meeting && is_binary(bot.meeting.title) && bot.meeting.title != "" ->
        bot.meeting.title

      bot.calendar_event && is_binary(bot.calendar_event.summary) && bot.calendar_event.summary != "" ->
        bot.calendar_event.summary

      true ->
        "Recorded Meeting"
    end
  end
end
