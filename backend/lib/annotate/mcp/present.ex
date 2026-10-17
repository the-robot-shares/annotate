defmodule Annotate.MCP.Present do
  @moduledoc """
  Serialization of sites, threads and comments for MCP tools/resources.

  **Untrusted-field labelling (prompt-injection guard).** Every value a
  website visitor (or another site member) can write — comment bodies,
  author names, page titles, quoted text, anchors, URLs, site names — is
  placed under an `untrusted` key (or a field prefixed `untrusted_`). Fields
  outside `untrusted` are server-derived: ids, statuses, timestamps, counts,
  roles, and `deep_link`, which is only present when the thread's URL origin
  is one of the site's `allowed_origins` (`Annotate.Anchors.safe_deep_link/3`).
  """

  alias Annotate.Schema.Annotate.Site

  @excerpt 280
  @attachment_ttl 300

  def site(%Site{} = site, role, extra \\ %{}) do
    Map.merge(
      %{
        slug: site.slug,
        role: to_string(role),
        untrusted: %{name: site.name}
      },
      extra
    )
  end

  def site_config(%Site{} = site, role, counts) do
    policy = site.comment_policy || %{}

    %{
      slug: site.slug,
      role: to_string(role),
      allowed_origins: site.allowed_origins || [],
      counts: counts,
      policy: %{
        public_read: Annotate.Sites.public_read?(site),
        allow_anonymous: Annotate.Sites.allow_anonymous?(site),
        read_visibility: to_string(Annotate.Sites.read_visibility(site)),
        trust_host_roles: Annotate.Sites.trust_host_roles?(site),
        page_key_strategy: to_string(Annotate.Sites.page_key_strategy(site)),
        moderation: Map.get(policy, "moderation")
      },
      untrusted: %{name: site.name}
    }
  end

  def thread_summary(thread, %Site{} = site) do
    comments = live_comments(thread)
    first = List.first(comments)
    last = List.last(comments)

    %{
      id: thread.id,
      site: site.slug,
      status: to_string(thread.status),
      created_at: iso(thread.inserted_at),
      resolved_at: iso(thread.resolved_at),
      last_activity_at: iso((last && last.inserted_at) || thread.inserted_at),
      orphaned: not is_nil(thread.orphaned_at),
      comment_count: length(comments),
      team_replied: Enum.any?(comments, &team?/1),
      page_path: thread.page_path || (loaded(thread.page) && thread.page.page_key),
      deep_link: Annotate.Anchors.safe_deep_link(site, thread.url, thread.id),
      untrusted: %{
        url: thread.url,
        page_title: thread.page_title,
        first_comment_excerpt: first && excerpt(first.body_md),
        first_author: first && author_name(first)
      }
    }
  end

  def thread_detail(thread, %Site{} = site) do
    comments = live_comments(thread)

    %{
      id: thread.id,
      site: site.slug,
      status: to_string(thread.status),
      created_at: iso(thread.inserted_at),
      resolved_at: iso(thread.resolved_at),
      orphaned: not is_nil(thread.orphaned_at),
      page_path: thread.page_path || (loaded(thread.page) && thread.page.page_key),
      page_key: loaded(thread.page) && thread.page.page_key,
      origin_allowed: Annotate.Anchors.url_on_site?(site, thread.url),
      deep_link: Annotate.Anchors.safe_deep_link(site, thread.url, thread.id),
      comments: Enum.map(comments, &comment/1),
      untrusted: %{
        url: thread.url,
        page_title: thread.page_title,
        query_string: thread.query_string,
        anchor: thread.anchor
      }
    }
  end

  def comment(c) do
    attachments = if loaded(c.attachments), do: c.attachments, else: []

    %{
      id: c.id,
      parent_id: c.parent_id,
      created_at: iso(c.inserted_at),
      edited_at: iso(c.edited_at),
      team: team?(c),
      attachments: Enum.map(attachments, &attachment/1),
      untrusted: %{author_name: author_name(c), body: c.body_md || ""}
    }
  end

  defp attachment(a) do
    %{
      id: a.id,
      kind: to_string(a.kind),
      content_type: a.content_type,
      bytes: a.bytes,
      width: a.width,
      height: a.height,
      download_url: download_url(a),
      download_url_expires_in: @attachment_ttl
    }
  end

  defp download_url(%{status: :ready, storage_key: key}) when is_binary(key) do
    Annotate.Storage.presigned_download_url(key, @attachment_ttl)
  rescue
    _ -> nil
  end

  defp download_url(_), do: nil

  defp live_comments(%{comments: comments}) when is_list(comments),
    do: Enum.reject(comments, &(not is_nil(&1.deleted_at)))

  defp live_comments(_), do: []

  defp team?(c), do: loaded(c.author) != nil and not is_nil(c.author.user_id)

  defp author_name(c) do
    case loaded(c.author) do
      %{display_name: name} when is_binary(name) and name != "" -> name
      _ -> "Guest"
    end
  end

  defp excerpt(nil), do: ""
  defp excerpt(body), do: String.slice(body, 0, @excerpt)

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(other), do: other

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(other), do: to_string(other)
end
