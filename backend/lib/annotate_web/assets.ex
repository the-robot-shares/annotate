defmodule AnnotateWeb.Assets do
  @moduledoc """
  Content-hash cache busting for first-party static assets served through
  Cloudflare (`max-age=14400`): `versioned("/css/landing.css")` ->
  `"/css/landing.css?v=<md5-8>"`. Without this a deploy can leave the edge
  serving a stale stylesheet against new markup (the landing loop list showed
  native `4.` markers plus a wrong `01` counter that way).

  The hash is computed once per path (persistent_term) from the file shipped in
  the release's `priv/static`; a missing file returns the bare path.
  """

  @spec versioned(String.t()) :: String.t()
  def versioned("/" <> rel = path) do
    key = {__MODULE__, path}

    case :persistent_term.get(key, nil) do
      nil ->
        v = hash(rel)
        :persistent_term.put(key, v)
        with_version(path, v)

      v ->
        with_version(path, v)
    end
  end

  defp with_version(path, nil), do: path
  defp with_version(path, v), do: path <> "?v=" <> v

  defp hash(rel) do
    file = Path.join(Application.app_dir(:annotate, "priv/static"), rel)

    case File.read(file) do
      {:ok, bin} -> :crypto.hash(:md5, bin) |> Base.encode16(case: :lower) |> binary_part(0, 8)
      _ -> nil
    end
  end
end
