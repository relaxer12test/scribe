defmodule SocialScribeWeb.HomeLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Calendar
  alias SocialScribe.CalendarSyncronizer
  alias SocialScribe.Bots

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :sync_calendars)

    socket =
      socket
      |> assign(:page_title, "Upcoming Meetings")
      |> assign(:events, Calendar.list_upcoming_events(socket.assigns.current_user))
      |> assign(:reauth_required, [])
      |> assign(:loading, true)
      |> assign(:timezone, "Etc/UTC")

    {:ok, socket}
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => timezone}, socket) do
    {:noreply, assign(socket, :timezone, normalize_timezone(timezone))}
  end

  @impl true
  def handle_event("toggle_record", %{"id" => event_id}, socket) do
    event = Calendar.get_calendar_event!(event_id)

    {:ok, event} =
      Calendar.update_calendar_event(event, %{record_meeting: not event.record_meeting})

    send(self(), {:schedule_bot, event})

    updated_events =
      Enum.map(socket.assigns.events, fn e ->
        if e.id == event.id, do: event, else: e
      end)

    {:noreply, assign(socket, :events, updated_events)}
  end

  @impl true
  def handle_info({:schedule_bot, event}, socket) do
    socket =
      if event.record_meeting do
        case Bots.create_and_dispatch_bot(socket.assigns.current_user, event) do
          {:ok, _} ->
            socket

          {:error, reason} ->
            Logger.error("Failed to create bot: #{inspect(reason)}")
            put_flash(socket, :error, "Failed to schedule recording bot. Please check your Recall API configuration.")
        end
      else
        case Bots.cancel_and_delete_bot(event) do
          {:ok, _} -> socket
          {:error, reason} ->
            Logger.error("Failed to cancel bot: #{inspect(reason)}")
            socket
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:sync_calendars, socket) do
    sync_result = CalendarSyncronizer.sync_events_for_user(socket.assigns.current_user)

    events = Calendar.list_upcoming_events(socket.assigns.current_user)

    socket =
      socket
      |> apply_sync_result(sync_result)
      |> assign(:events, events)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  defp apply_sync_result(socket, {:error, {:reauth_required, credentials}}) do
    count = length(credentials)

    message =
      if count == 1 do
        "Reconnect your Google account to resume calendar sync."
      else
        "Reconnect your Google accounts to resume calendar sync."
      end

    socket
    |> put_flash(:error, message)
    |> assign(:reauth_required, credentials)
  end

  defp apply_sync_result(socket, _result) do
    assign(socket, :reauth_required, [])
  end

  defp normalize_timezone(timezone) when is_binary(timezone) do
    case Timex.Timezone.get(timezone, DateTime.utc_now()) do
      %Timex.TimezoneInfo{} -> timezone
      %Timex.AmbiguousTimezoneInfo{} -> timezone
      _ -> "Etc/UTC"
    end
  end

  defp normalize_timezone(_timezone), do: "Etc/UTC"

  defp format_event_time(%DateTime{} = datetime, timezone) do
    datetime
    |> shift_to_timezone(timezone)
    |> Timex.format!("%m/%d/%Y, %H:%M:%S", :strftime)
  end

  defp shift_to_timezone(%DateTime{} = datetime, timezone) when is_binary(timezone) do
    case Timex.Timezone.convert(datetime, timezone) do
      %Timex.AmbiguousDateTime{before: before} -> before
      %DateTime{} = converted -> converted
      {:error, _} -> datetime
    end
  end

  defp shift_to_timezone(datetime, _timezone), do: datetime
end
