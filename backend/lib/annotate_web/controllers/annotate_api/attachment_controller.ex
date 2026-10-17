defmodule AnnotateWeb.AnnotateAPI.AttachmentController do
  @moduledoc """
  Attachment upload endpoints (token required; uploader = token subject):

  - `POST /api/v1/attachments/presign?site=<slug>` — validates the content-type
    allowlist and `settings.max_upload_mb`, then returns a presigned PUT url
    and registers a `pending` attachment. Images are hard-capped at 1 MB
    (declared size); every other kind keeps the site's `max_upload_mb`.
  - `POST /api/v1/attachments/:id/complete` — `pending` → `ready`. Verifies
    the upload's ACTUAL byte size (images: 1 MB) by fetching the stored
    object, runs it through `Annotate.Moderation` (images: vision model;
    `text/plain`: text model; PDFs: not classified), rejects with a
    user-facing message on failure (object + row deleted, nothing stored),
    then enforces the rolling storage cap
    (`Annotate.Storage.Rotation`).
  """
  use AnnotateWeb, :controller

  require Logger

  alias Annotate.Comments
  alias Annotate.Moderation
  alias Annotate.Sites
  alias Annotate.Storage
  alias Annotate.Storage.Rotation
  alias AnnotateWeb.AnnotateAPI.Renderer

  @allowed_content_types ~w(
    image/png image/jpeg image/webp image/gif application/pdf text/plain
  )

  # Hard per-image cap (declared AND actual bytes). Not configurable: 1 MB.
  @image_cap_bytes 1024 * 1024

  def presign(conn, params) do
    site = conn.assigns.annotate_site
    uploader = conn.assigns.annotate_commenter

    with {:ok, kind} <- validate_kind(params["kind"]),
         :ok <- validate_content_type(params["content_type"]),
         :ok <- validate_bytes(site, params["bytes"], params["content_type"]),
         {:ok, filename} <- validate_filename(params["filename"]),
         # In-chain (not a body match): billing gates return
         # {:error, :billing_read_only | :plan_storage_limit} — an error tuple
         # must reach the else clauses, never raise at the body's `=`.
         {:ok, attachment, upload_url} <-
           Comments.create_pending_attachment(site, uploader, %{
             filename: filename,
             content_type: params["content_type"],
             bytes: params["bytes"],
             kind: kind
           }) do
      conn
      |> put_status(:created)
      |> json(%{
        "attachment" => Renderer.attachment(attachment),
        "upload_url" => upload_url
      })
    else
      {:error, "image_too_large"} ->
        conn
        |> put_status(413)
        |> json(%{
          "error" => "image_too_large",
          "message" => "That image is too large. Please upload an image of 1 MB or less."
        })

      {:error, "too_large"} ->
        conn |> put_status(413) |> json(%{"error" => "too_large"})

      {:error, :billing_read_only} ->
        conn
        |> put_status(:forbidden)
        |> json(%{"error" => "billing_read_only", "message" => Annotate.Billing.locked_message()})

      {:error, :plan_storage_limit} ->
        conn
        |> put_status(413)
        |> json(%{
          "error" => "storage_limit_reached",
          "message" =>
            "The site owner's storage plan is full. Upgrades are on the annotate dashboard Billing page."
        })

      {:error, code} when is_binary(code) ->
        conn |> put_status(:bad_request) |> json(%{"error" => code})

      {:error, %Ecto.Changeset{}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{"error" => "invalid_request"})
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
            case admit_attachment(attachment) do
              # :ok and :storage_unavailable both proceed to the actual state
              # change; finish_complete/3 keeps every status mapping (incl.
              # 409 not_pending on a second complete) in one place.
              outcome when outcome in [:ok, {:error, :storage_unavailable}] ->
                if outcome == {:error, :storage_unavailable} do
                  # Fail-open on the size/moderation leg (the declared size was
                  # already checked at presign); completing is still allowed.
                  Logger.warning(
                    "[attachments] stored object unreadable, failing open id=#{attachment.id}"
                  )
                end

                finish_complete(conn, attachment, params)

              {:error, :too_large} ->
                Comments.reject_pending_attachment(attachment)

                conn
                |> put_status(413)
                |> json(%{
                  "error" => "image_too_large",
                  "message" => "That image is too large. Please upload an image of 1 MB or less."
                })

              {:error, :content_rejected} ->
                Comments.reject_pending_attachment(attachment)

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{
                  "error" => "content_rejected",
                  "message" =>
                    "That attachment doesn't meet this community's content guidelines. Please remove or replace it."
                })
            end
        end

      nil ->
        conn |> put_status(:not_found) |> json(%{"error" => "not_found"})
    end
  end

  defp finish_complete(conn, attachment, params) do
    case Comments.complete_attachment(attachment, params) do
      {:ok, attachment} ->
        run_rotation()
        json(conn, %{"attachment" => Renderer.attachment(attachment)})

      {:error, :not_pending} ->
        conn |> put_status(:conflict) |> json(%{"error" => "not_pending"})

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{"error" => "invalid_request"})
    end
  end

  # Actual-bytes size check + moderation, on the STORED object. `:ok` admits,
  # `{:error, :storage_unavailable}` fail-opens, everything else rejects.
  defp admit_attachment(attachment) do
    cond do
      image?(attachment.content_type) ->
        with {:ok, %{body: body}} <- Storage.get_object(attachment.storage_key) do
          cond do
            byte_size(body) > @image_cap_bytes -> {:error, :too_large}
            true -> Moderation.check_attachment(attachment.content_type, body)
          end
        else
          {:error, reason} ->
            Logger.warning(
              "[attachments] object fetch failed id=#{attachment.id}: #{inspect(reason)}"
            )

            {:error, :storage_unavailable}
        end

      attachment.content_type == "text/plain" ->
        with {:ok, %{body: body}} <- Storage.get_object(attachment.storage_key) do
          Moderation.check_attachment("text/plain", body)
        else
          {:error, reason} ->
            Logger.warning(
              "[attachments] object fetch failed id=#{attachment.id}: #{inspect(reason)}"
            )

            {:error, :storage_unavailable}
        end

      # PDFs and other kinds are not classified (fail-open, like the filter).
      true ->
        :ok
    end
  end

  # Rolling 1GB comment-attachment cap; never fails the response.
  defp run_rotation do
    case Rotation.enforce() do
      {:ok, 0} -> :ok
      {:ok, n} -> Logger.info("[attachments] storage rotation evicted #{n} attachment(s)")
      {:error, reason} -> Logger.warning("[attachments] storage rotation error: #{inspect(reason)}")
    end
  rescue
    e -> Logger.warning("[attachments] storage rotation crashed: #{inspect(e.__struct__)}")
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

  # Images: hard 1 MB cap on the DECLARED size (the actual bytes are verified
  # against the stored object at complete). Everything else keeps the site's
  # per-site `max_upload_mb`.
  defp validate_bytes(site, bytes, content_type)

  defp validate_bytes(_site, bytes, "image/" <> _) when is_integer(bytes) and bytes > 0 do
    if bytes <= @image_cap_bytes, do: :ok, else: {:error, "image_too_large"}
  end

  defp validate_bytes(site, bytes, _ct) when is_integer(bytes) and bytes > 0 do
    max = Sites.max_upload_mb(site) * 1024 * 1024

    if bytes <= max, do: :ok, else: {:error, "too_large"}
  end

  defp validate_bytes(_site, _bytes, _ct), do: {:error, "invalid_request"}

  defp image?("image/" <> _), do: true
  defp image?(_), do: false

  defp validate_filename(f) when is_binary(f) and byte_size(f) in 1..1024, do: {:ok, f}
  defp validate_filename(_), do: {:error, "invalid_request"}
end
