defmodule AnnotateWeb.AnnotateAPI.SiteConfigController do
  @moduledoc """
  `GET /api/v1/sites/:site/config` — public-safe, no-PII widget bootstrap
  config (feature plan: replaces widget guesswork, future-proofs composer
  defaults).

  `team` is true when the presented (site-bound, verified) access token's
  commenter is on the site's team RIGHT NOW (`Annotate.Embed.Team.current_role/3`,
  re-derived per request, not read off the claim). No role, member list or
  other PII is returned. Anonymous requests are served like any other read
  (subject to `settings.public_read` via the `:annotate_auth_optional` plug).

  The viewer's permission keys (`Annotate.Embed.Visibility.permissions/3`:
  `authenticated, role, staff, can_read_all, can_moderate, can_post,
  read_visibility`) are merged in, and served alone by
  `GET /api/v1/sites/:site/me` (`me/2`). All computed live per request.
  """

  use AnnotateWeb, :controller

  alias Annotate.Sites

  alias Annotate.Embed.Visibility

  def show(conn, _params) do
    site = conn.assigns.annotate_site

    json(
      conn,
      Map.merge(permissions(conn), %{
        "site" => site.slug,
        "default_visibility" => Atom.to_string(Sites.default_visibility(site)),
        "public_read" => Sites.public_read?(site),
        "allow_anonymous" => Sites.allow_anonymous?(site),
        "max_upload_mb" => Sites.max_upload_mb(site),
        "page_key_strategy" => Sites.page_key_strategy(site),
        "team" => team?(site, conn.assigns[:annotate_commenter], conn.assigns[:annotate_claims])
      })
    )
  end

  @doc "`GET /api/v1/sites/:site/me` — the viewer's live permission map."
  def me(conn, _params), do: json(conn, permissions(conn))

  defp permissions(conn) do
    Visibility.permissions(
      conn.assigns.annotate_site,
      conn.assigns[:annotate_commenter],
      conn.assigns[:annotate_claims]
    )
  end

  defp team?(_site, nil, _claims), do: false

  defp team?(site, commenter, claims),
    do: Annotate.Embed.Team.current_role(site, commenter, claims) != nil
end
