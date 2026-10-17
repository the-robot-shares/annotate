defmodule AnnotateWeb.DashboardAttachmentController do
  @moduledoc """
  Authenticated 302 to a fresh presigned download for one comment attachment.

  The inbox shows `/dashboard/attachments/:id` links; because presigned urls
  expire in ~5 minutes, the link itself is stable and every hit re-signs at
  request time — inbox thumbnails never go stale.

  Authorization mirrors the inbox (`Annotate.Hologram.DashboardAuth.authorize_site/3`):
  dashboard session (`AnnotateWeb.Plugs.DashboardSession`), invite gate
  (`Annotate.Dashboard.Access.allowed?/1`), and **member+ of the attachment's
  site** read from the DB per request. A non-member gets the same `404` a
  nonexistent id gets — no existence oracle across tenants.
  """

  use AnnotateWeb, :controller

  alias Annotate.Dashboard.Access
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Attachment
  alias Annotate.SiteMembers
  alias Annotate.Sites

  def show(conn, %{"id" => raw_id}) do
    with {:session, %{id: user_id} = user} <- {:session, conn.assigns[:dashboard_user]},
         {:invite, true} <- {:invite, Access.allowed?(user)},
         {:id, {:ok, id}} <- {:id, Ecto.UUID.cast(raw_id)},
         {:attachment, %Attachment{} = a} <- {:attachment, Repo.get(Attachment, id)},
         {:ready, true} <-
           {:ready, a.status == :ready and is_binary(a.storage_key)},
         {:site, %{} = site} <- {:site, Sites.get_site(a.site_id)},
         {:member, role} when role != nil <- {:member, SiteMembers.member_role(site, user_id)} do
      url = download_url(a, image?(a))
      # The redirect target carries the short-lived signature: never cache it.
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> redirect(external: url)
    else
      {:session, _} ->
        # Same redirect the Hologram RequireAuth middleware performs.
        conn |> put_resp_header("cache-control", "private, no-store") |> redirect(to: "/sign-in")

      {:member, _} ->
        not_found(conn)

      _ ->
        not_found(conn)
    end
  end

  def show(conn, _params), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  # Images/screenshot render inline so <img> thumbnails and the lightbox work;
  # everything else is forced to download (Content-Disposition via the signed
  # query). Sign for 5 min: the redirect is consumed immediately.
  defp download_url(a, true), do: sign(a.storage_key, [])
  defp download_url(a, false), do: sign(a.storage_key, disposition: basename(a))

  defp sign(key, opts), do: Annotate.Storage.presigned_download_url(key, 300, opts)

  defp basename(a), do: a.storage_key |> String.split("/") |> List.last()

  defp image?(%{kind: kind}) when kind in [:image, :screenshot], do: true

  defp image?(%{content_type: ct}) when is_binary(ct),
    do: String.starts_with?(ct, "image/")

  defp image?(_), do: false
end
