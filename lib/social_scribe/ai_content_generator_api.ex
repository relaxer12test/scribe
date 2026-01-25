defmodule SocialScribe.AIContentGeneratorApi do
  @moduledoc """
  Behaviour for generating AI content for meetings.
  """

  @callback generate_follow_up_email(map()) :: {:ok, String.t()} | {:error, any()}
  @callback generate_automation(map(), map()) :: {:ok, String.t()} | {:error, any()}
  @callback generate_hubspot_suggestions(map()) :: {:ok, list(map())} | {:error, any()}
  @callback generate_salesforce_suggestions(map()) :: {:ok, list(map())} | {:error, any()}
  @callback generate_chat_response(
              user_query :: String.t(),
              mentioned_contacts :: list(map()),
              meeting_context :: list(map()),
              conversation_history :: list(map())
            ) :: {:ok, map()} | {:error, any()}
  @callback generate_chat_response_stream(
              user_query :: String.t(),
              mentioned_contacts :: list(map()),
              meeting_context :: list(map()),
              conversation_history :: list(map()),
              callback :: (String.t() -> any())
            ) :: {:ok, map()} | {:error, any()}

  @optional_callbacks [generate_chat_response_stream: 5]

  def generate_follow_up_email(meeting) do
    impl().generate_follow_up_email(meeting)
  end

  def generate_automation(automation, meeting) do
    impl().generate_automation(automation, meeting)
  end

  def generate_hubspot_suggestions(meeting) do
    impl().generate_hubspot_suggestions(meeting)
  end

  def generate_salesforce_suggestions(meeting) do
    impl().generate_salesforce_suggestions(meeting)
  end

  def generate_chat_response(user_query, mentioned_contacts, meeting_context, conversation_history) do
    impl().generate_chat_response(user_query, mentioned_contacts, meeting_context, conversation_history)
  end

  def generate_chat_response_stream(user_query, mentioned_contacts, meeting_context, conversation_history, callback) do
    impl().generate_chat_response_stream(user_query, mentioned_contacts, meeting_context, conversation_history, callback)
  end

  defp impl do
    Application.get_env(
      :social_scribe,
      :ai_content_generator_api,
      SocialScribe.AIContentGenerator
    )
  end
end
