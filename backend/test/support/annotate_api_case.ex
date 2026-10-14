defmodule AnnotateWeb.AnnotateAPICase do
  @moduledoc """
  Shared setup for annotate API tests: throwaway site + commenter/token
  helpers, all against the sandboxed Repo.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Annotate.DataCase
      import AnnotateWeb.AnnotateAPICase

      @endpoint AnnotateWeb.Endpoint

      @good_origin "https://good.example"
      @evil_origin "https://evil.example"
      @site_host "annotate-srv.therobotlives.com"
    end
  end

  setup tags do
    Annotate.DataCase.setup_sandbox(tags)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:host, "annotate-srv.therobotlives.com")

    {:ok, conn: conn}
  end

  @doc "Creates a site (allowed_origins default [https://good.example]) → {site, service_key}."
  def create_site(opts \\ []) do
    slug = "site-#{System.unique_integer([:positive])}"

    {:ok, site, key} =
      Annotate.Sites.create_site(%{
        "slug" => slug,
        "name" => "Site #{slug}",
        "allowed_origins" => Keyword.get(opts, :origins, ["https://good.example"]),
        "settings" =>
          Keyword.get(opts, :settings, %{
            "public_read" => true,
            "page_key_strategy" => "strip_query_hash",
            "max_upload_mb" => 20
          }),
        "comment_policy" => Keyword.get(opts, :comment_policy, %{}),
        "owner_commenter_id" => nil
      })

    {site, key}
  end

  @doc "Makes `commenter` the owner of `site` (site-owner delete rights)."
  def set_owner!(site, commenter) do
    Annotate.Sites.set_site_owner(site, commenter)
  end

  def create_commenter(attrs \\ []) do
    n = System.unique_integer([:positive])

    {:ok, commenter} =
      %Annotate.Schema.Annotate.Commenter{}
      |> Annotate.Schema.Annotate.Commenter.changeset(%{
        authentik_sub: Keyword.get(attrs, :authentik_sub),
        external_id: Keyword.get(attrs, :external_id),
        site_id: Keyword.get(attrs, :site_id),
        display_name: Keyword.get(attrs, :display_name, "Commenter #{n}"),
        email: Keyword.get(attrs, :email)
      })
      |> Annotate.Repo.insert()

    commenter
  end

  @doc "Issues an access token bound to (commenter, site, origin)."
  def issue_access(commenter, site, origin \\ "https://good.example") do
    Annotate.Auth.ApiToken.issue_access(commenter, site, origin)
  end

  def auth_header(token), do: {"authorization", "Bearer #{token}"}
  def origin_header(origin), do: {"origin", origin}

  def site_param(site), do: %{"site" => site.slug}

  @doc "Creates a thread (page upsert + root comment) and returns the thread."
  def create_thread!(site, commenter, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "page_key" => "/some/page",
          "url" => "https://good.example/some/page",
          "title" => "Some Page",
          "anchor" => %{"css" => "h1"},
          "body_md" => "first!"
        },
        attrs
      )

    {:ok, thread} = Annotate.Comments.create_thread(site, commenter, attrs)
    thread
  end
end
