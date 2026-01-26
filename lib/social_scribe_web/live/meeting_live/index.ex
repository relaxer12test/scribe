defmodule SocialScribeWeb.MeetingLive.Index do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo

  alias SocialScribe.Meetings

  @impl true
  def mount(_params, session, socket) do
    meeting_items = Meetings.list_user_meeting_items(socket.assigns.current_user)
    timezone = normalize_timezone(session["browser_timezone"])

    socket =
      socket
      |> assign(:page_title, "Meetings")
      |> assign(:meeting_items, meeting_items)
      |> assign(:timezone, timezone)

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    meeting_items = Meetings.list_user_meeting_items(socket.assigns.current_user)
    {:noreply, assign(socket, :meeting_items, meeting_items)}
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    "#{minutes} min"
  end

  defp format_meeting_time(nil, _timezone), do: "N/A"

  defp format_meeting_time(%DateTime{} = datetime, timezone) do
    datetime
    |> shift_to_timezone(timezone)
    |> Timex.format!("%m/%d/%Y, %H:%M:%S", :strftime)
  end

  defp format_meeting_time(datetime, _timezone), do: to_string(datetime)

  defp normalize_timezone(timezone) when is_binary(timezone) do
    case Timex.Timezone.get(timezone, DateTime.utc_now()) do
      %Timex.TimezoneInfo{} -> timezone
      %Timex.AmbiguousTimezoneInfo{} -> timezone
      _ -> "Etc/UTC"
    end
  end

  defp normalize_timezone(_timezone), do: "Etc/UTC"

  defp shift_to_timezone(%DateTime{} = datetime, timezone) when is_binary(timezone) do
    case Timex.Timezone.convert(datetime, timezone) do
      %Timex.AmbiguousDateTime{before: before} -> before
      %DateTime{} = converted -> converted
      {:error, _} -> datetime
    end
  end

  defp shift_to_timezone(datetime, _timezone), do: datetime

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
