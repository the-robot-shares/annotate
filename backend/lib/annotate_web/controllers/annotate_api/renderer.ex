defmodule AnnotateWeb.AnnotateAPI.Renderer do
  @moduledoc "JSON serialization for the annotate API payloads."

  alias Annotate.Comments

  def thread_list(threads) do
    Enum.map(threads, &thread/1)
  end

  def thread(%{} = t) do
    %{
      "id" => t.id,
      "status" => to_string(t.status),
      # Boolean convenience for widgets (tobor-kit reads `resolved`).
      "resolved" => t.status == :resolved,
      "anchor" => t.anchor,
      "anchor_version" => t.anchor_version,
      "url" => t.url,
      "origin" => t.origin,
      "page_path" => t.page_path,
      "query_string" => t.query_string,
      "query_params" => t.query_params,
      "hash" => t.hash,
      "page_title" => t.page_title,
      "deep_link" => Annotate.Anchors.deep_link(t.url, t.id),
      "orphaned_at" => t.orphaned_at,
      "resolved_at" => t.resolved_at,
      "created_by" => t.creator && author(t.creator),
      "created_at" => t.inserted_at,
      "updated_at" => t.updated_at,
      "comments" => Enum.map(safe_list(t.comments), &comment/1)
    }
  end

  def comment(%{} = c) do
    %{
      "id" => c.id,
      "thread_id" => c.thread_id,
      "parent_id" => c.parent_id,
      "author" => c.author && author(c.author),
      "body_md" => c.body_md,
      "edited_at" => c.edited_at,
      "inserted_at" => c.inserted_at,
      "attachments" => Enum.map(safe_list(c.attachments), &attachment/1)
    }
  end

  def author(nil), do: nil
  def author(%Ecto.Association.NotLoaded{}), do: nil

  def author(a) do
    %{
      "id" => a.id,
      "display_name" => a.display_name,
      "avatar_url" => a.avatar_url,
      "authentik" => not is_nil(a.authentik_sub),
      "external" => not is_nil(a.external_id),
      # Replies written from the owner dashboard (site team identity).
      "team" => not is_nil(Map.get(a, :user_id))
    }
  end

  def attachment(%{} = a) do
    %{
      "id" => a.id,
      # Widgets (tobor-kit parseAttachment) require a string filename; the
      # sanitized upload name is the last segment of the storage key.
      "filename" => filename(a),
      "kind" => to_string(a.kind),
      "content_type" => a.content_type,
      "bytes" => a.bytes,
      "width" => a.width,
      "height" => a.height,
      "annotation" => a.annotation,
      "status" => to_string(a.status),
      "url" => download_url(a),
      "inserted_at" => a.inserted_at
    }
  end

  def commenter(c) do
    %{
      "id" => c.id,
      "display_name" => c.display_name,
      "avatar_url" => c.avatar_url,
      "email" => email_present?(c)
    }
  end

  defp email_present?(c), do: not is_nil(c.email)

  defp filename(%{storage_key: key}) when is_binary(key) and key != "", do: Path.basename(key)
  defp filename(_), do: "attachment"

  defp download_url(a), do: Comments.presign_downloads([a]) |> Map.get(a.id)
  defp safe_list(list) when is_list(list), do: list
  defp safe_list(_), do: []
end
