defmodule AnnotateWeb.Assets do
  @moduledoc """
  Content-hash cache busting for first-party static assets served through
  Cloudflare (`max-age=14400`): `versioned("/css/landing.css")` ->
  `"/css/landing.css?v=<md5-8>"`. Without this a deploy can leave the edge
  serving a stale stylesheet against new markup (the landing loop list showed
  native `4.` markers plus a wrong `01` counter that way).

  Digests are computed once at boot (`warm/0`, called from
  `Annotate.Application.start/2`) and kept in the application env.

  **Client-safe on purpose.** `versioned/1` is called from Hologram
  layout/component templates, so the compiled browser bundle runs it during
  hydration. The client has no filesystem and no `:asset_digests` env, so it
  gets the bare path — never a `File`/`:crypto`/`:code.lib_dir` call (the
  previous persistent_term + File.read version crashed hydration on every page
  with `Function :code.lib_dir/1 is not yet ported`, leaving the dashboard
  inbox stuck on "Loading comments…").
  """

  @app :annotate

  @doc "Hash priv/static css+js once per boot for `versioned/1`. Never raises."
  @spec warm() :: :ok
  def warm do
    digests =
      try do
        compute_digests()
      rescue
        _ -> %{}
      end

    Application.put_env(@app, :asset_digests, digests)
    :ok
  end

  @spec versioned(String.t()) :: String.t()
  def versioned("/" <> rel = path) do
    case Application.get_env(@app, :asset_digests) do
      # Client runtime (or a cold server): no digests, plain path.
      nil -> path
      digests -> with_version(path, digests["/" <> rel])
    end
  end

  defp compute_digests do
    static = Application.app_dir(@app, "priv/static")

    static
    |> Path.join("**/*.{css,js}")
    |> Path.wildcard()
    |> Map.new(fn file ->
      {"/" <> Path.relative_to(file, static), file_digest(file)}
    end)
  end

  defp file_digest(file) do
    case File.read(file) do
      {:ok, bin} -> :crypto.hash(:md5, bin) |> Base.encode16(case: :lower) |> binary_part(0, 8)
      _ -> nil
    end
  end

  defp with_version(path, nil), do: path
  defp with_version(path, v), do: path <> "?v=" <> v
end
