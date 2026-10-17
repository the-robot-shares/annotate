defmodule AnnotateWeb.WaitlistController do
  @moduledoc """
  `POST /waitlist` — landing-page waitlist. Rate limited
  (`Plugs.RateLimit, action: :waitlist`), honeypot-guarded, and answers both
  JSON (the page's script) and a plain HTML thank-you page (no-JS form post).
  """
  use AnnotateWeb, :controller

  def create(conn, params) do
    case Annotate.Waitlist.signup(params) do
      {:ok, _n} ->
        respond(conn, 200, "ok", nil)

      {:error, :invalid_email} ->
        respond(conn, 422, "invalid_email", "Enter a valid email address.")

      {:error, :no_interest} ->
        respond(conn, 422, "no_interest", "Pick at least one thing to hear about.")
    end
  end

  defp respond(conn, status, code, message) do
    if json?(conn) do
      body = if status == 200, do: %{ok: true}, else: %{ok: false, error: code, message: message}
      conn |> put_status(status) |> json(body)
    else
      page(conn, status, message)
    end
  end

  defp json?(conn) do
    accept = conn |> get_req_header("accept") |> Enum.join(",")
    ctype = conn |> get_req_header("content-type") |> Enum.join(",")
    String.contains?(accept, "json") or String.contains?(ctype, "json")
  end

  defp page(conn, status, message) do
    {title, text} =
      if status == 200,
        do: {"You're on the list", "We'll email you when it ships. Nothing else."},
        else: {"Almost", message}

    html = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex"><title>#{title} · annotate</title>
    <style>body{font:18px/1.5 system-ui,sans-serif;background:#0b0b10;color:#d6d6e4;display:grid;place-items:center;min-height:100vh;margin:0}
    main{max-width:34rem;padding:2rem}a{color:#fb923c}</style></head>
    <body><main><h1>#{title}</h1><p>#{text}</p><p><a href="/#waitlist">Back to annotate</a></p></main></body></html>
    """

    conn |> put_resp_content_type("text/html") |> send_resp(status, html)
  end
end
