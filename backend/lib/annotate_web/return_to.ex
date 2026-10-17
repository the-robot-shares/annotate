defmodule AnnotateWeb.ReturnTo do
  @moduledoc """
  Same-origin validation for post-sign-in `return_to` destinations.

  The MCP authorization server (`Annotate.MCP.Bridge.login_url/2`) sends a
  signed-out user to `/sign-in?return_to=<issuer>/oauth/authorize?login_state=…`.
  That value crosses the GitHub/Google round trip and comes back as a query
  parameter, so it is attacker-reachable: `safe/1` is the single gate and is
  applied on every hop (sign-in page, `SSOController.prepare_oauth`, the
  `/auth/sso-callback` page).

  Accepted, normalized to a path (+ query):

    * a relative path starting with exactly one `/` (`/oauth/authorize?…`);
    * an absolute URL whose scheme + host + port equal the MCP issuer origin
      (`Annotate.MCP.Config.issuer/0`) — the library builds absolute URLs.

  Rejected (nil): protocol-relative `//evil`, `/\\evil`, any other origin,
  `javascript:` and every non-http(s) scheme, control characters/whitespace,
  fragments, and anything over 2048 bytes.
  """

  @max 2048

  @spec safe(term()) :: String.t() | nil
  def safe(value) when is_binary(value) and byte_size(value) in 1..@max do
    cond do
      String.match?(value, ~r/[\x00-\x20\x7f\\#]/) -> nil
      String.starts_with?(value, "//") -> nil
      String.starts_with?(value, "/") -> path_of(URI.parse(value))
      true -> absolute(URI.parse(value))
    end
  end

  def safe(_), do: nil

  defp absolute(%URI{scheme: scheme, host: host} = uri)
       when scheme in ["http", "https"] and is_binary(host) do
    if origin(uri) == issuer_origin(), do: path_of(uri), else: nil
  end

  defp absolute(_), do: nil

  defp path_of(%URI{path: "/" <> _ = path, query: query, userinfo: nil}) do
    if String.starts_with?(path, "//"),
      do: nil,
      else: path <> if(query, do: "?" <> query, else: "")
  end

  defp path_of(_), do: nil

  defp issuer_origin do
    case Application.get_env(:annotate, :mcp, [])[:issuer] do
      issuer when is_binary(issuer) -> origin(URI.parse(issuer))
      _ -> :none
    end
  end

  defp origin(%URI{scheme: scheme, host: host, port: port}) when is_binary(host) do
    {String.downcase(scheme || ""), String.downcase(host), port}
  end

  defp origin(_), do: :none
end
