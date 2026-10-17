defmodule Annotate.Anchors do
  @moduledoc """
  Page-context capture + matching for thread anchors (anchor fidelity).

  A thread records WHERE it was written: full `url`, `origin`, normalized
  `page_path`, `query_string` (raw) + `query_params` (map), `hash`, and the
  page title — next to the element anchor jsonb. Everything is derived from
  the submitted `url` when present (server-authoritative), falling back to
  client-supplied fields for url-less writers.

  Query matching is order-insensitive and per-site configurable:

      sites.settings["anchor"] = %{
        "ignore_query_params"      => ["utm_*", "fbclid"],  # trailing * = prefix
        "significant_query_params" => []                    # non-empty = allow-list
      }

  Default (absent) = every query param is significant. A thread with
  `query_params == nil` (legacy rows) matches any query.
  """

  alias Annotate.Schema.Annotate.Site

  @max_params 64
  @max_value 512

  @doc "Decomposes a URL into the stored page-context fields. `nil` if unusable."
  def parse_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when scheme in ["http", "https"] and is_binary(host) ->
        %{
          "url" => url,
          "origin" => origin(uri),
          "page_path" => normalize_path(uri.path),
          "query_string" => uri.query || "",
          "query_params" => parse_query(uri.query),
          "hash" => clean_hash(uri.fragment)
        }

      _ ->
        nil
    end
  end

  def parse_url(_), do: nil

  @doc """
  Page-context attrs for a new thread from request params. Derived from
  `params["url"]`; client-supplied `page_path`/`query_string`/`query_params`/
  `hash` fill in when the url cannot be parsed.
  """
  def context_from_params(params) when is_map(params) do
    derived = parse_url(params["url"]) || %{}

    fallback_query = bounded_string(params["query_string"], 4096)

    base = %{
      "url" => bounded_string(params["url"], 4096),
      "origin" => derived["origin"],
      "page_path" => derived["page_path"] || normalize_path(params["page_path"]),
      "query_string" => derived["query_string"] || fallback_query,
      "query_params" =>
        derived["query_params"] ||
          sanitize_params(params["query_params"]) ||
          if(fallback_query, do: parse_query(fallback_query)),
      "hash" => derived["hash"] || clean_hash(params["hash"]),
      "page_title" => bounded_string(params["title"] || params["page_title"], 512)
    }

    Map.new(base, fn {k, v} -> {k, v} end)
  end

  # ── Query parsing / normalization ────────────────────────────────

  @doc "Raw query string -> map. Repeated keys collapse to a sorted list."
  def parse_query(nil), do: %{}
  def parse_query(""), do: %{}

  def parse_query(query) when is_binary(query) do
    query
    |> String.trim_leading("?")
    |> URI.query_decoder()
    |> Enum.take(@max_params)
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.update(acc, k, [v], &[v | &1])
    end)
    |> Map.new(fn
      {k, [v]} -> {k, v}
      {k, vs} -> {k, Enum.sort(vs)}
    end)
  rescue
    _ -> %{}
  end

  defp sanitize_params(%{} = map) do
    map
    |> Enum.take(@max_params)
    |> Enum.flat_map(fn
      {k, v} when is_binary(k) and is_binary(v) ->
        [{k, String.slice(v, 0, @max_value)}]

      {k, vs} when is_binary(k) and is_list(vs) ->
        [{k, vs |> Enum.filter(&is_binary/1) |> Enum.map(&String.slice(&1, 0, @max_value)) |> Enum.sort()}]

      _ ->
        []
    end)
    |> Map.new()
  end

  defp sanitize_params(_), do: nil

  @doc "Strips ignored params (and non-allow-listed ones when an allow-list is set)."
  def significant(nil, _cfg), do: nil

  def significant(%{} = params, cfg) do
    ignore = cfg["ignore_query_params"] || []
    allow = cfg["significant_query_params"] || []

    params
    |> Enum.reject(fn {k, _} -> matches_any?(k, ignore) end)
    |> Enum.filter(fn {k, _} -> allow == [] or matches_any?(k, allow) end)
    |> Map.new(fn {k, v} -> {k, List.wrap(v) |> Enum.sort()} end)
  end

  defp matches_any?(key, patterns) do
    Enum.any?(patterns, fn
      p when is_binary(p) ->
        if String.ends_with?(p, "*"),
          do: String.starts_with?(key, String.trim_trailing(p, "*")),
          else: key == p

      _ ->
        false
    end)
  end

  @doc """
  True when a thread stored with `thread_params` belongs on a page currently
  showing `current_params`. Order-insensitive; nil stored params match any.
  """
  def query_match?(nil, _current, _cfg), do: true

  def query_match?(thread_params, current_params, cfg) do
    significant(thread_params, cfg) == significant(current_params || %{}, cfg)
  end

  # ── Site config ──────────────────────────────────────────────────

  @doc "Anchor config (`ignore_query_params`, `significant_query_params`) with request overrides unioned in."
  def config(%Site{settings: settings}, extra_ignore \\ []) do
    cfg = (is_map(settings) && settings["anchor"]) || %{}

    %{
      "ignore_query_params" =>
        Enum.uniq(List.wrap(cfg["ignore_query_params"]) ++ List.wrap(extra_ignore)),
      "significant_query_params" => List.wrap(cfg["significant_query_params"])
    }
  end

  # ── Deep link ────────────────────────────────────────────────────

  @doc "`url` (sans fragment) + `#annotate=<thread_id>`; nil when the thread has no url."
  def deep_link(nil, _id), do: nil

  def deep_link(url, id) when is_binary(url) do
    base = url |> String.split("#", parts: 2) |> hd()
    base <> "#annotate=" <> id
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp origin(%URI{scheme: s, host: h, port: p}) do
    default = if s == "https", do: 443, else: 80
    s <> "://" <> String.downcase(h) <> if(p in [nil, default], do: "", else: ":#{p}")
  end

  @doc "Path normalization: leading slash, no trailing slash (root stays `/`)."
  def normalize_path(nil), do: nil
  def normalize_path(""), do: "/"

  def normalize_path(path) when is_binary(path) do
    path = path |> String.split(["?", "#"], parts: 2) |> hd()
    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path

    case String.trim_trailing(path, "/") do
      "" -> "/"
      p -> String.slice(p, 0, 1024)
    end
  end

  def normalize_path(_), do: nil

  # The deep-link token itself is not page state.
  defp clean_hash(nil), do: nil
  defp clean_hash(""), do: nil

  defp clean_hash(h) when is_binary(h) do
    h = String.trim_leading(h, "#")
    if String.starts_with?(h, "annotate="), do: nil, else: String.slice(h, 0, 1024)
  end

  defp clean_hash(_), do: nil

  defp bounded_string(s, max) when is_binary(s) and s != "", do: String.slice(s, 0, max)
  defp bounded_string(_, _), do: nil
end
