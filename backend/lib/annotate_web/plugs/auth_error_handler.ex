defmodule AnnotateWeb.AuthErrorHandler do
  import Plug.Conn

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  # <REMOVED UUID HERE> auth_error :: auto-generated pointer for public function auth_error
  def auth_error(conn, {type, _reason}, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: to_string(type)}))
  end
end
