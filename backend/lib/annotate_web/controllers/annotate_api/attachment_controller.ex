defmodule AnnotateWeb.AnnotateAPI.AttachmentController do
  @moduledoc """
  Attachment upload endpoints (token required; uploader = token subject):

  - `POST /api/v1/attachments/presign?site=<slug>` — validates the content-type
    allowlist and `settings.max_upload_mb`, then returns a presigned PUT url
    and registers a `pending` attachment.
  - `POST /api/v1/attachments/:id/complete` — `pending` → `ready` with
    optional width/height/annotation.
  """
  use AnnotateWeb, :controller

  alias Annotate.Comments
  alias Annotate.Sites
  alias AnnotateWeb.AnnotateAPI.Renderer

  @allowed_content_types ~w(
    image/png image/jpeg image/webp image/gif application/pdf text/plain
  )

  def presign(conn, params) do
    site = conn.assigns.annotate_site
    uploader = conn.assigns.annotate_commenter

    with {:ok, kind} <- validate_kind(params["kind"]),
         :ok <- validate_content_type(params["content_type"]),
         :ok <- validate_bytes(site, params["bytes"]),
         {:ok, filename} <- validate_filename(params["filename"]) do
      {:ok, attachment, upload_url} =
        Comments.create_pending_attachment(site, uploader, %{
          filename: filename,
          content_type: params["content_type"],
          bytes: params["bytes"],
          kind: kind
        })

      conn
      |> put_status(:created)
      |> json(%{
        "attachment" => Renderer.attachment(attachment),
        "upload_url" => upload_url
      })
    else
      {:error, "too_large"} ->
        conn |> put_status(413) |> json(%{"error" => "too_large"})

      {:error, code} when is_binary(code) ->
        conn |> put_status(:bad_request) |> json(%{"error" => code})
    end
  end

  def complete(conn, params) do
    site = conn.assigns.annotate_site
    uploader = conn.assigns.annotate_commenter

    case Comments.get_attachment_for_site(params["id"], site.id) do
      %Annotate.Schema.Annotate.Attachment{} = attachment ->
        cond do
          # Only the uploader may complete their own pending attachment.
          is_nil(uploader) or attachment.uploader_id != uploader.id ->
            conn |> put_status(:forbidden) |> json(%{"error" => "forbidden"})

          true ->
            case Comments.complete_attachment(attachment, params) do
              {:ok, attachment} ->
                json(conn, %{"attachment" => Renderer.attachment(attachment)})

              {:error, :not_pending} ->
                conn
                |> put_status(:conflict)
                |> json(%{"error" => "not_pending"})

              {:error, _} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{"error" => "invalid_request"})
            end
        end

      nil ->
        conn |> put_status(:not_found) |> json(%{"error" => "not_found"})
    end
  end

  # ── Validation ───────────────────────────────────────────────

  defp validate_kind(nil), do: {:ok, :file}

  defp validate_kind(kind) when kind in ~w(file image screenshot),
    do: {:ok, String.to_existing_atom(kind)}

  defp validate_kind(_), do: {:error, "invalid_kind"}

  defp validate_content_type(ct) when is_binary(ct) do
    if ct in @allowed_content_types, do: :ok, else: {:error, "unsupported_content_type"}
  end

  defp validate_content_type(_), do: {:error, "content_type_required"}

  defp validate_bytes(site, bytes) when is_integer(bytes) and bytes > 0 do
    max = Sites.max_upload_mb(site) * 1024 * 1024

    if bytes <= max, do: :ok, else: {:error, "too_large"}
  end

  defp validate_bytes(_site, _bytes), do: {:error, "invalid_request"}

  defp validate_filename(f) when is_binary(f) and byte_size(f) in 1..1024, do: {:ok, f}
  defp validate_filename(_), do: {:error, "invalid_request"}
end
