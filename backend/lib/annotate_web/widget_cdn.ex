defmodule AnnotateWeb.WidgetCdn do
  @moduledoc """
  Where the comment widget (tobor-kit `<noizu-page-comments>`) is loaded from.

  tobor-kit publishes every release to cdn.derobot.is under
  `tobor-kit/v<X.Y.Z>/` (immutable), plus moving `tobor-kit/v<X>/` and
  `tobor-kit/latest/` aliases (short TTL). Each release ships `annotate.js`,
  a loader that registers the widget from that same release.

  annotate's own pages pin the exact version (`pinned_src/0`) so a deploy is
  reproducible; customer snippets default to `latest_src/0` and offer the
  pinned form. Bump `@version` to move annotate to a new tobor-kit release.
  """

  @version "1.0.8"
  @base "https://cdn.derobot.is/tobor-kit"

  @doc "tobor-kit release annotate pins."
  def version, do: @version

  @doc "Exact-version loader (immutable, reproducible)."
  def pinned_src, do: "#{@base}/v#{@version}/annotate.js"

  @doc "Always-newest loader (moves with each tobor-kit release)."
  def latest_src, do: "#{@base}/latest/annotate.js"

  @doc """
  The kit's `noizu-auth` module from the same release as `widget_src`
  (accepts either `annotate.js` or `components/page-comments/page-comments.js`).
  """
  # Plain string patterns only: this runs inside Hologram templates on the
  # client, where Regex (:re.import/1) is not ported.
  def auth_src(widget_src) when is_binary(widget_src) do
    widget_src
    |> String.replace(
      "components/page-comments/page-comments.js",
      "components/auth/noizu-auth.js"
    )
    |> String.replace("/annotate.js", "/components/auth/noizu-auth.js")
  end
end
