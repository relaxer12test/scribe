defmodule SocialScribe.Workers.BotStatusPoller do
  use Oban.Worker, queue: :polling, max_attempts: 3

  alias SocialScribe.Bots
  alias SocialScribe.RecallApi
  alias SocialScribe.Meetings

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    bots_to_poll = Bots.list_pending_bots()

    if Enum.any?(bots_to_poll) do
      Logger.info("Polling #{Enum.count(bots_to_poll)} pending Recall.ai bots...")
    end

    for bot_record <- bots_to_poll do
      poll_and_process_bot(bot_record)
    end

    :ok
  end

  defp poll_and_process_bot(bot_record) do
    case RecallApi.get_bot(bot_record.recall_bot_id) do
      {:ok, %Tesla.Env{body: bot_api_info}} ->
        new_status = latest_status(bot_api_info) || bot_record.status

        {:ok, updated_bot_record} = Bots.update_recall_bot(bot_record, %{status: new_status})
        meeting = Meetings.get_meeting_by_recall_bot_id(updated_bot_record.id)

        cond do
          new_status == "done" && is_nil(meeting) ->
            process_completed_bot(updated_bot_record, bot_api_info)

          is_nil(meeting) && recordings_present?(bot_api_info) ->
            case fetch_transcript_data(updated_bot_record.recall_bot_id) do
              {:ok, transcript_data} ->
                if transcript_available?(transcript_data) do
                  case process_completed_bot(updated_bot_record, bot_api_info,
                         transcript_data: transcript_data,
                         allow_empty_transcript: false
                       ) do
                    {:ok, _meeting} ->
                      Bots.update_recall_bot(updated_bot_record, %{status: "done"})

                    {:error, _reason} ->
                      :ok
                  end
                end

              _ ->
                :ok
            end

          true ->
            if new_status != bot_record.status do
              Logger.info("Bot #{bot_record.recall_bot_id} status updated to: #{new_status}")
            end
        end

      {:error, reason} ->
        Logger.error(
          "Failed to poll bot status for #{bot_record.recall_bot_id}: #{inspect(reason)}"
        )

        Bots.update_recall_bot(bot_record, %{status: "polling_error"})
    end
  end

  defp process_completed_bot(bot_record, bot_api_info, opts \\ []) do
    Logger.info("Bot #{bot_record.recall_bot_id} is done. Fetching transcript and participants...")

    allow_empty_transcript = Keyword.get(opts, :allow_empty_transcript, true)

    transcript_data =
      case Keyword.fetch(opts, :transcript_data) do
        {:ok, data} ->
          data

        :error ->
          case fetch_transcript_data(bot_record.recall_bot_id) do
            {:ok, data} ->
              data

            {:error, reason} ->
              Logger.warning(
                "Failed to fetch transcript for bot #{bot_record.recall_bot_id}: #{inspect(reason)}"
              )

              if allow_empty_transcript, do: [], else: :unavailable
          end
      end

    {:ok, participants_data} = fetch_participants(bot_record.recall_bot_id)

    if transcript_data == :unavailable do
      {:error, :transcript_unavailable}
    else
      Logger.info("Fetched data for bot #{bot_record.recall_bot_id}. Creating meeting record...")

      case Meetings.create_meeting_from_recall_data(
             bot_record,
             bot_api_info,
             transcript_data,
             participants_data
           ) do
        {:ok, meeting} ->
          Logger.info(
            "Successfully created meeting record #{meeting.id} from bot #{bot_record.recall_bot_id}"
          )

          SocialScribe.Workers.AIContentGenerationWorker.new(%{meeting_id: meeting.id})
          |> Oban.insert()

          Logger.info("Enqueued AI content generation for meeting #{meeting.id}")
          {:ok, meeting}

        {:error, reason} ->
          Logger.error(
            "Failed to create meeting record from bot #{bot_record.recall_bot_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp fetch_participants(recall_bot_id) do
    case RecallApi.get_bot_participants(recall_bot_id) do
      {:ok, %Tesla.Env{body: participants_data}} ->
        {:ok, participants_data}

      {:error, reason} ->
        Logger.warning("Could not fetch participants for bot #{recall_bot_id}: #{inspect(reason)}, falling back to empty list")
        {:ok, []}
    end
  end

  defp latest_status(bot_api_info) do
    status_changes =
      Map.get(bot_api_info, :status_changes) || Map.get(bot_api_info, "status_changes") || []

    status_changes
    |> List.last()
    |> then(fn
      nil -> nil
      last -> Map.get(last, :code, Map.get(last, "code"))
    end)
  end

  defp recordings_present?(bot_api_info) do
    recordings = Map.get(bot_api_info, :recordings) || Map.get(bot_api_info, "recordings") || []
    Enum.any?(recordings)
  end

  defp fetch_transcript_data(recall_bot_id) do
    case RecallApi.get_bot_transcript(recall_bot_id) do
      {:ok, %Tesla.Env{body: data}} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp transcript_available?(data) when is_list(data), do: data != []
  defp transcript_available?(data) when is_binary(data), do: String.trim(data) != ""
  defp transcript_available?(data) when is_map(data), do: map_size(data) > 0
  defp transcript_available?(_data), do: false
end
