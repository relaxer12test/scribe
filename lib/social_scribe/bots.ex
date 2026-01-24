defmodule SocialScribe.Bots do
  @moduledoc """
  The Bots context.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo

  alias SocialScribe.Bots.RecallBot
  alias SocialScribe.Bots.UserBotPreference
  alias SocialScribe.Accounts.User
  alias SocialScribe.Meetings
  alias SocialScribe.RecallApi
  alias SocialScribe.Workers.AIContentGenerationWorker

  @doc """
  Returns the list of recall_bots.

  ## Examples

      iex> list_recall_bots()
      [%RecallBot{}, ...]

  """
  def list_recall_bots do
    Repo.all(RecallBot)
  end

  @doc """
  Lists all bots whose status is not yet "done" or "error".
  These are the bots that the poller should check.
  """
  def list_pending_bots do
    from(b in RecallBot, where: b.status not in ["done", "error", "polling_error"])
    |> Repo.all()
  end

  @doc """
  Gets a single recall_bot.

  Raises `Ecto.NoResultsError` if the Recall bot does not exist.

  ## Examples

      iex> get_recall_bot!(123)
      %RecallBot{}

      iex> get_recall_bot!(456)
      ** (Ecto.NoResultsError)

  """
  def get_recall_bot!(id), do: Repo.get!(RecallBot, id)

  @doc """
  Creates a recall_bot.

  ## Examples

      iex> create_recall_bot(%{field: value})
      {:ok, %RecallBot{}}

      iex> create_recall_bot(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_recall_bot(attrs \\ %{}) do
    %RecallBot{}
    |> RecallBot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a recall_bot.

  ## Examples

      iex> update_recall_bot(recall_bot, %{field: new_value})
      {:ok, %RecallBot{}}

      iex> update_recall_bot(recall_bot, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_recall_bot(%RecallBot{} = recall_bot, attrs) do
    recall_bot
    |> RecallBot.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a recall_bot.

  ## Examples

      iex> delete_recall_bot(recall_bot)
      {:ok, %RecallBot{}}

      iex> delete_recall_bot(recall_bot)
      {:error, %Ecto.Changeset{}}

  """
  def delete_recall_bot(%RecallBot{} = recall_bot) do
    Repo.delete(recall_bot)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking recall_bot changes.

  ## Examples

      iex> change_recall_bot(recall_bot)
      %Ecto.Changeset{data: %RecallBot{}}

  """
  def change_recall_bot(%RecallBot{} = recall_bot, attrs \\ %{}) do
    RecallBot.changeset(recall_bot, attrs)
  end

  # --- Orchestration Functions ---

  @doc """
  Orchestrates creating a bot via the API and saving it to the database.
  """
  def create_and_dispatch_bot(user, calendar_event) do
    user_bot_preference = get_user_bot_preference(user.id) || %UserBotPreference{}
    join_minute_offset = user_bot_preference.join_minute_offset

    with {:ok, %{status: status, body: api_response}} when status in 200..299 <-
           RecallApi.create_bot(
             calendar_event.hangout_link,
             DateTime.add(
               calendar_event.start_time,
               -join_minute_offset,
               :minute
             )
           ),
         %{id: bot_id} <- api_response do
      status = get_in(api_response, [:status_changes, Access.at(0), :code]) || "ready"

      create_recall_bot(%{
        user_id: user.id,
        calendar_event_id: calendar_event.id,
        recall_bot_id: bot_id,
        meeting_url: calendar_event.hangout_link,
        status: status
      })
    else
      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, {status, body}}}

      {:error, reason} ->
        {:error, {:api_error, reason}}

      _ ->
        {:error, {:api_error, :invalid_response}}
    end
  end

  @doc """
  Orchestrates deleting a bot via the API and removing it from the database.
  """
  def cancel_and_delete_bot(calendar_event) do
    case Repo.get_by(RecallBot, calendar_event_id: calendar_event.id) do
      nil ->
        {:ok, :no_bot_to_cancel}

      %RecallBot{} = bot ->
        case RecallApi.delete_bot(bot.recall_bot_id) do
          {:ok, %{status: 404}} -> delete_recall_bot(bot)
          {:ok, _} -> delete_recall_bot(bot)
          {:error, reason} -> {:error, {:api_error, reason}}
        end
    end
  end

  @doc """
  Orchestrates updating a bot's schedule via the API and saving it to the database.
  """
  def update_bot_schedule(bot, calendar_event) do
    user_bot_preference = get_user_bot_preference(bot.user_id) || %UserBotPreference{}
    join_minute_offset = user_bot_preference.join_minute_offset

    with {:ok, %{body: api_response}} <-
           RecallApi.update_bot(
             bot.recall_bot_id,
             calendar_event.hangout_link,
             DateTime.add(calendar_event.start_time, -join_minute_offset, :minute)
           ) do
      update_recall_bot(bot, %{
        status: api_response.status_changes |> List.first() |> Map.get(:code)
      })
    end
  end

  @doc """
  Refreshes a recall bot and creates a meeting when transcript data is available.
  """
  def refresh_bot_and_meeting(%User{} = user, bot_id) when is_integer(bot_id) do
    case Repo.get_by(RecallBot, id: bot_id, user_id: user.id) do
      nil -> {:error, :not_found}
      bot -> refresh_bot_and_meeting(bot)
    end
  end

  def refresh_bot_and_meeting(%RecallBot{} = bot_record) do
    case RecallApi.get_bot(bot_record.recall_bot_id) do
      {:ok, %Tesla.Env{body: bot_api_info}} ->
        new_status = latest_status(bot_api_info) || bot_record.status

        with {:ok, updated_bot_record} <- update_recall_bot(bot_record, %{status: new_status}) do
          meeting = Meetings.get_meeting_by_recall_bot_id(updated_bot_record.id)

          cond do
            is_nil(meeting) && new_status == "done" ->
              case create_meeting_from_bot(updated_bot_record, bot_api_info,
                     allow_empty_transcript: false
                   ) do
                {:ok, :pending} -> {:ok, :pending}
                {:ok, _meeting} -> {:ok, :meeting_created}
                {:error, reason} -> {:error, reason}
              end

            is_nil(meeting) && recordings_present?(bot_api_info) ->
              case fetch_transcript_data(updated_bot_record.recall_bot_id) do
                {:ok, transcript_data} ->
                  if transcript_available?(transcript_data) do
                    case create_meeting_from_bot(updated_bot_record, bot_api_info,
                           transcript_data: transcript_data,
                           allow_empty_transcript: false
                         ) do
                      {:ok, _meeting} ->
                        update_recall_bot(updated_bot_record, %{status: "done"})
                        {:ok, :meeting_created}

                      {:error, reason} ->
                        {:error, reason}
                    end
                  else
                    {:ok, :pending}
                  end

                {:error, reason} ->
                  {:error, reason}
              end

            is_nil(meeting) ->
              {:ok, :pending}

            true ->
              {:ok, :already_processed}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the list of user_bot_preferences.

  ## Examples

      iex> list_user_bot_preferences()
      [%UserBotPreference{}, ...]

  """
  def list_user_bot_preferences do
    Repo.all(UserBotPreference)
  end

  @doc """
  Gets a single user_bot_preference.

  Raises `Ecto.NoResultsError` if the User bot preference does not exist.

  ## Examples

      iex> get_user_bot_preference!(123)
      %UserBotPreference{}

      iex> get_user_bot_preference!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user_bot_preference!(id), do: Repo.get!(UserBotPreference, id)

  def get_user_bot_preference(user_id) do
    Repo.get_by(UserBotPreference, user_id: user_id)
  end

  @doc """
  Creates a user_bot_preference.

  ## Examples

      iex> create_user_bot_preference(%{field: value})
      {:ok, %UserBotPreference{}}

      iex> create_user_bot_preference(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_bot_preference(attrs \\ %{}) do
    %UserBotPreference{}
    |> UserBotPreference.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_bot_preference.

  ## Examples

      iex> update_user_bot_preference(user_bot_preference, %{field: new_value})
      {:ok, %UserBotPreference{}}

      iex> update_user_bot_preference(user_bot_preference, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_bot_preference(%UserBotPreference{} = user_bot_preference, attrs) do
    user_bot_preference
    |> UserBotPreference.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_bot_preference.

  ## Examples

      iex> delete_user_bot_preference(user_bot_preference)
      {:ok, %UserBotPreference{}}

      iex> delete_user_bot_preference(user_bot_preference)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user_bot_preference(%UserBotPreference{} = user_bot_preference) do
    Repo.delete(user_bot_preference)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_bot_preference changes.

  ## Examples

      iex> change_user_bot_preference(user_bot_preference)
      %Ecto.Changeset{data: %UserBotPreference{}}

  """
  def change_user_bot_preference(%UserBotPreference{} = user_bot_preference, attrs \\ %{}) do
    UserBotPreference.changeset(user_bot_preference, attrs)
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

  defp fetch_participants(recall_bot_id) do
    case RecallApi.get_bot_participants(recall_bot_id) do
      {:ok, %Tesla.Env{body: participants_data}} -> {:ok, participants_data}
      {:error, _reason} -> {:ok, []}
    end
  end

  defp create_meeting_from_bot(bot_record, bot_api_info, opts) do
    allow_empty_transcript = Keyword.get(opts, :allow_empty_transcript, true)

    transcript_data =
      case Keyword.fetch(opts, :transcript_data) do
        {:ok, data} ->
          data

        :error ->
          case fetch_transcript_data(bot_record.recall_bot_id) do
            {:ok, data} -> data
            {:error, _reason} -> if allow_empty_transcript, do: [], else: :unavailable
          end
      end

    {:ok, participants_data} = fetch_participants(bot_record.recall_bot_id)

    if transcript_data == :unavailable do
      {:ok, :pending}
    else
      case Meetings.create_meeting_from_recall_data(
             bot_record,
             bot_api_info,
             transcript_data,
             participants_data
           ) do
        {:ok, meeting} ->
          AIContentGenerationWorker.new(%{meeting_id: meeting.id})
          |> Oban.insert()

          {:ok, meeting}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
