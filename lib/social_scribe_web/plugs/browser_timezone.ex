defmodule SocialScribeWeb.Plugs.BrowserTimezone do
  import Plug.Conn

  @cookie "browser_timezone"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    timezone = conn.req_cookies[@cookie]

    if is_binary(timezone) and timezone != "" do
      put_session(conn, :browser_timezone, timezone)
    else
      conn
    end
  end
end
