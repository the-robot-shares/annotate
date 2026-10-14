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
      "anchor" => t.anchor,
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
      "external" => not is_nil(a.external_id)
    }
  end

  def attachment(%{} = a) do
    %{
      "id" => a.id,
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

  defp download_url(a), do: Comments.presign_downloads([a]) |> Map.get(a.id)
  defp safe_list(list) when is_list(list), do: list
  defp safe_list(_), do: []
end
