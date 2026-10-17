defmodule AnnotateWeb.Plugs.RawBodyReader do
  @moduledoc """
  `Plug.Parsers` `:body_reader` that caches the raw request body in
  `conn.private[:raw_body]`. The Stripe webhook (`BillingWebhookController`)
  must verify its signature over the exact bytes on the wire, and the global
  parsers in `AnnotateWeb.Endpoint` have already consumed the stream by the
  time a controller runs. Chunked reads accumulate, so bodies larger than one
  read-buffer are still verified whole.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, Plug.Conn.put_private(conn, :raw_body, raw_so_far(conn, body))}

      {:more, partial, conn} ->
        {:more, partial, Plug.Conn.put_private(conn, :raw_body, raw_so_far(conn, partial))}

      {:error, _reason} = error ->
        error
    end
  end

  defp raw_so_far(conn, chunk) do
    case conn.private[:raw_body] do
      prev when is_binary(prev) -> prev <> chunk
      _ -> chunk
    end
  end
end
