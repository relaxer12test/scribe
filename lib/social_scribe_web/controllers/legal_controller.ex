defmodule SocialScribeWeb.LegalController do
  use SocialScribeWeb, :controller

  def privacy(conn, _params) do
    contact_email = contact_email()

    render(conn, :privacy,
      page_title: "Privacy Policy",
      contact_email: contact_email
    )
  end

  def delete(conn, _params) do
    contact_email = contact_email()
    {subject, body} = deletion_email_template()

    render(conn, :delete,
      page_title: "Data Deletion Instructions",
      contact_email: contact_email,
      mailto: mailto_link(contact_email, subject, body),
      mailto_subject: subject,
      mailto_body: body
    )
  end

  def terms(conn, _params) do
    render(conn, :terms,
      page_title: "Terms of Service",
      contact_email: contact_email()
    )
  end

  defp contact_email do
    Application.get_env(:social_scribe, :privacy_contact_email, "support@ldev.cloud")
  end

  defp deletion_email_template do
    subject = "Data Deletion Request - Social Scribe"

    body =
      """
      Hello Social Scribe Team,

      I am requesting deletion of my Social Scribe data.

      Account email:
      Facebook user ID (if available):
      Connected Facebook Page IDs (if applicable):
      Additional details:

      Thank you,
      """
      |> String.trim()

    {subject, body}
  end

  defp mailto_link(email, subject, body) do
    query = URI.encode_query(%{"subject" => subject, "body" => body})
    "mailto:#{email}?#{query}"
  end
end
