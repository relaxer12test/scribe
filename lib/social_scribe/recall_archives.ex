defmodule SocialScribe.RecallArchives do
  @moduledoc """
  Stores Recall.ai recordings separately from the Meetings flow.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo

  alias SocialScribe.Accounts.User
  alias SocialScribe.RecallApi
  alias SocialScribe.RecallArchives.RecallArchive

  require Logger

  def list_user_archives(%User{} = user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)

    from(a in RecallArchive,
      where: a.user_id == ^user.id,
      order_by: [desc: a.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_archive!(id), do: Repo.get!(RecallArchive, id)

  def get_archive_by_recall_bot_id(user_id, recall_bot_id) do
    Repo.get_by(RecallArchive, user_id: user_id, recall_bot_id: recall_bot_id)
  end

  def fetch_bot_by_query(query) do
    query = query |> to_string() |> String.trim()

    cond do
      query == "" ->
        {:error, :empty_query}

      looks_like_url?(query) ->
        fetch_bot_by_meeting_url(query)

      true ->
        fetch_bot_by_id(query)
    end
  end

  def import_bot(%User{} = user, bot_info, source_meeting_url \\ nil) do
    recall_bot_id = bot_id(bot_info)

    transcript_data =
      case RecallApi.get_bot_transcript(recall_bot_id) do
        {:ok, %Tesla.Env{body: data}} ->
          data

        {:error, reason} ->
          Logger.warning(
            "Recall archive transcript fetch failed for #{recall_bot_id}: #{inspect(reason)}"
          )

          []
      end

    participants_data =
      case RecallApi.get_bot_participants(recall_bot_id) do
        {:ok, %Tesla.Env{body: data}} ->
          data

        {:error, reason} ->
          Logger.warning(
            "Recall archive participants fetch failed for #{recall_bot_id}: #{inspect(reason)}"
          )

          []
      end

    attrs =
      build_archive_attrs(user, bot_info, transcript_data, participants_data, source_meeting_url)

    upsert_archive(attrs)
  end

  def bot_status(bot_info) do
    status_changes =
      Map.get(bot_info, :status_changes) || Map.get(bot_info, "status_changes") || []

    status_changes
    |> List.last()
    |> then(fn
      nil -> nil
      last -> Map.get(last, :code, Map.get(last, "code"))
    end)
  end

  def bot_id(bot_info) do
    Map.get(bot_info, :id, Map.get(bot_info, "id"))
  end

  defp fetch_bot_by_id(recall_bot_id) do
    case RecallApi.get_bot(recall_bot_id) do
      {:ok, %Tesla.Env{body: bot_info}} ->
        {:ok, %{bot: bot_info, source_meeting_url: nil}}

      {:error, reason} ->
        {:error, {:api_error, reason}}
    end
  end

  defp fetch_bot_by_meeting_url(meeting_url) do
    case RecallApi.list_bots(%{meeting_url: meeting_url}) do
      {:ok, %Tesla.Env{body: body}} ->
        results = Map.get(body, :results, Map.get(body, "results", []))

        case results do
          [] ->
            {:error, :not_found}

          bots ->
            {:ok, %{bot: pick_best_bot(bots), source_meeting_url: meeting_url}}
        end

      {:error, reason} ->
        {:error, {:api_error, reason}}
    end
  end

  defp pick_best_bot(bots) do
    Enum.find(bots, fn bot -> bot_status(bot) == "done" end) || List.first(bots)
  end

  defp upsert_archive(attrs) do
    now = DateTime.utc_now()

    set_attrs =
      attrs
      |> Map.take([
        :meeting_url,
        :status,
        :title,
        :recorded_at,
        :duration_seconds,
        :transcript,
        :participants,
        :bot_metadata
      ])
      |> Map.put(:updated_at, now)

    %RecallArchive{}
    |> RecallArchive.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: set_attrs],
      conflict_target: [:user_id, :recall_bot_id]
    )
  end

  defp build_archive_attrs(user, bot_info, transcript_data, participants_data, source_meeting_url) do
    recordings = Map.get(bot_info, :recordings) || Map.get(bot_info, "recordings") || []
    recording_info = List.first(recordings) || %{}

    recorded_at = parse_datetime(recording_info[:started_at] || recording_info["started_at"])
    completed_at = parse_datetime(recording_info[:completed_at] || recording_info["completed_at"])

    duration_seconds =
      if recorded_at && completed_at do
        DateTime.diff(completed_at, recorded_at, :second)
      else
        nil
      end

    %{
      user_id: user.id,
      recall_bot_id: bot_id(bot_info),
      meeting_url: source_meeting_url || meeting_url_to_string(bot_info),
      status: bot_status(bot_info),
      title: extract_title(bot_info, recording_info),
      recorded_at: recorded_at,
      duration_seconds: duration_seconds,
      transcript: normalize_transcript(transcript_data),
      participants: normalize_json(participants_data),
      bot_metadata: normalize_json(bot_info)
    }
  end

  defp normalize_transcript(transcript_data) do
    parsed =
      case transcript_data do
        data when is_binary(data) -> Jason.decode!(data)
        data when is_list(data) -> data
        _ -> []
      end

    normalized = normalize_json(parsed) || []

    %{
      "data" => normalized,
      "language" => extract_language(normalized)
    }
  end

  defp extract_language([first | _]) when is_map(first) do
    Map.get(first, "language") || Map.get(first, :language)
  end

  defp extract_language(_), do: nil

  defp normalize_json(nil), do: nil

  defp normalize_json(data) do
    data
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp looks_like_url?(query) do
    String.contains?(query, "http://") ||
      String.contains?(query, "https://") ||
      String.contains?(query, "meet.google.com") ||
      String.contains?(query, "zoom.us")
  end

  defp meeting_url_to_string(bot_info) do
    meeting_url = Map.get(bot_info, :meeting_url, Map.get(bot_info, "meeting_url"))

    cond do
      is_binary(meeting_url) ->
        meeting_url

      match?(%{platform: "google_meet", meeting_id: _}, meeting_url) ->
        "https://meet.google.com/#{meeting_url.meeting_id}"

      match?(%{"platform" => "google_meet", "meeting_id" => _}, meeting_url) ->
        "https://meet.google.com/#{meeting_url["meeting_id"]}"

      match?(%{meeting_id: _}, meeting_url) ->
        meeting_url.meeting_id

      match?(%{"meeting_id" => _}, meeting_url) ->
        meeting_url["meeting_id"]

      true ->
        nil
    end
  end

  defp extract_title(bot_info, recording_info) do
    get_nested(bot_info, [:meeting_metadata, :title]) ||
      get_nested(bot_info, [:meeting_metadata, :data, :title]) ||
      get_nested(recording_info, [:meeting_metadata, :data, :title]) ||
      get_nested(recording_info, [:media_shortcuts, :meeting_metadata, :data, :title])
  end

  defp get_nested(data, keys) do
    Enum.reduce_while(keys, data, fn key, acc ->
      cond do
        is_map(acc) && Map.has_key?(acc, key) ->
          {:cont, Map.get(acc, key)}

        is_map(acc) && Map.has_key?(acc, to_string(key)) ->
          {:cont, Map.get(acc, to_string(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(%DateTime{} = value), do: value

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _} -> parsed
      _ -> nil
    end
  end
end
