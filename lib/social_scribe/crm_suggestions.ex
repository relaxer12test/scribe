defmodule SocialScribe.CrmSuggestions do
  @moduledoc false

  def dedupe_by_field(suggestions) when is_list(suggestions) do
    suggestions
    |> Enum.with_index()
    |> Enum.group_by(fn {suggestion, _index} -> suggestion_field(suggestion) end)
    |> Enum.map(fn {_field, entries} -> pick_best(entries) end)
    |> Enum.sort_by(fn {index, _suggestion} -> index end)
    |> Enum.map(fn {_index, suggestion} -> suggestion end)
  end

  defp pick_best(entries) do
    {suggestion, index} =
      Enum.max_by(entries, fn {suggestion, index} ->
        {timestamp_seconds(suggestion), index}
      end)

    {index, suggestion}
  end

  defp suggestion_field(suggestion) do
    Map.get(suggestion, :field) || Map.get(suggestion, "field")
  end

  defp timestamp_seconds(suggestion) do
    timestamp = Map.get(suggestion, :timestamp) || Map.get(suggestion, "timestamp")
    timestamp_seconds_value(timestamp)
  end

  defp timestamp_seconds_value(timestamp) when is_binary(timestamp) do
    timestamp
    |> normalize_timestamp()
    |> parse_timestamp()
  end

  defp timestamp_seconds_value(_), do: -1

  defp normalize_timestamp(timestamp) do
    timestamp
    |> String.trim()
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
  end

  defp parse_timestamp(timestamp) do
    case String.split(timestamp, ":") do
      [minutes, seconds] ->
        parse_minutes_seconds(minutes, seconds)

      [hours, minutes, seconds] ->
        parse_hours_minutes_seconds(hours, minutes, seconds)

      _ ->
        -1
    end
  end

  defp parse_minutes_seconds(minutes, seconds) do
    with {mm, ""} <- Integer.parse(minutes),
         {ss, ""} <- Integer.parse(seconds) do
      mm * 60 + ss
    else
      _ -> -1
    end
  end

  defp parse_hours_minutes_seconds(hours, minutes, seconds) do
    with {hh, ""} <- Integer.parse(hours),
         {mm, ""} <- Integer.parse(minutes),
         {ss, ""} <- Integer.parse(seconds) do
      hh * 3600 + mm * 60 + ss
    else
      _ -> -1
    end
  end
end
