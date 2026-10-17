defmodule Annotate.SitesAdminTest do
  use Annotate.DataCase, async: true

  alias Annotate.Repo
  alias Annotate.Sites
  alias Annotate.SiteMembers
  alias Annotate.Schema.Annotate.Site
  alias Annotate.Schema.Users.User

  defp user!(email),
    do:
      Repo.insert!(%User{id: Ecto.UUID.generate(), email: email, status: :active, verified: true})

  defp create(user, slug, origins),
    do:
      Sites.create_site_with_owner(
        %{"slug" => slug, "name" => slug, "allowed_origins" => origins},
        user
      )

  describe "normalize_origins" do
    test "accepts exact origins, lowercases, dedupes" do
      assert {:ok, ["https://a.example", "https://b.example:8443", "http://localhost:4000"]} =
               Sites.normalize_origins([
                 "https://A.example",
                 " https://b.example:8443 ",
                 "http://localhost:4000",
                 "https://a.example"
               ])
    end

    test "rejects anything that is not an exact origin" do
      for bad <- [
            "*",
            "https://*.example.com",
            "https://a.example/",
            "https://a.example/path",
            "https://u@a.example",
            "https://a.example?q=1",
            "https://a.example#x",
            "http://a.example",
            "ftp://a.example",
            "https://a.example:99999",
            "a.example",
            ""
          ] do
        assert {:error, :invalid_origin} = Sites.normalize_origins([bad]),
               "accepted #{inspect(bad)}"
      end

      assert {:error, :invalid_origin} = Sites.normalize_origins("https://a.example")

      assert {:error, :invalid_origin} =
               Sites.normalize_origins(for i <- 1..21, do: "https://s#{i}.example")
    end
  end

  describe "create_site_with_owner" do
    test "atomic site + owner + key" do
      u = user!("c1@example.com")
      assert {:ok, site, key} = create(u, "c-one", ["https://c.example"])
      assert is_binary(key) and byte_size(key) > 20
      assert SiteMembers.member_role(site, u.id) == :owner
      assert site.allowed_origins == ["https://c.example"]
    end

    test "invalid origins create nothing" do
      u = user!("c2@example.com")
      assert {:error, :invalid_origin} = create(u, "c-two", ["*"])
      refute Sites.get_site_by_slug("c-two")
    end

    test "slug errors surface as a changeset; nothing persisted" do
      u = user!("c3@example.com")
      assert {:error, %Ecto.Changeset{}} = create(u, "Bad Slug", ["https://c.example"])
      assert {:ok, _, _} = create(u, "dup", [])
      assert {:error, %Ecto.Changeset{}} = create(u, "dup", [])
      assert Repo.aggregate(Site, :count) == 1
    end

    test "per-user ownership cap" do
      u = user!("c4@example.com")

      for i <- 1..Sites.max_owned_sites(), do: {:ok, _, _} = create(u, "cap-#{i}", [])

      assert {:error, :site_limit} = create(u, "cap-over", [])
    end
  end

  describe "update_site_display / update_site_security" do
    setup do
      u = user!("u1@example.com")
      {:ok, site, _} = create(u, "upd", ["https://u.example"])
      %{site: site}
    end

    test "display cannot touch origins, policy, slug or keys", %{site: site} do
      assert {:ok, s} =
               Sites.update_site_display(site, %{
                 "name" => "Renamed",
                 "slug" => "hijack",
                 "allowed_origins" => ["https://evil.example"],
                 "comment_policy" => %{"trust_host_roles" => true},
                 "service_key_hash" => "x",
                 "settings" => %{
                   "public_read" => false,
                   "default_visibility" => "internal",
                   "x" => 1
                 }
               })

      assert s.name == "Renamed" and s.slug == "upd"
      assert s.allowed_origins == ["https://u.example"]
      refute Sites.trust_host_roles?(s)
      assert s.service_key_hash == site.service_key_hash
      refute Sites.public_read?(s)
      assert Sites.default_visibility(s) == :internal
      refute Map.has_key?(s.settings, "x")
      assert Sites.page_key_strategy(s) == "strip_query_hash"
    end

    test "display validates values", %{site: site} do
      assert {:error, :invalid_settings} =
               Sites.update_site_display(site, %{"settings" => %{"max_upload_mb" => 0}})

      assert {:error, :invalid_settings} =
               Sites.update_site_display(site, %{
                 "settings" => %{"default_visibility" => "secret"}
               })
    end

    test "security updates origins + policy only", %{site: site} do
      assert {:ok, s} =
               Sites.update_site_security(site, %{
                 "allowed_origins" => ["https://New.example"],
                 "comment_policy" => %{"trust_host_roles" => true, "required_groups" => ["qa "]},
                 "name" => "nope"
               })

      assert s.allowed_origins == ["https://new.example"]
      assert Sites.trust_host_roles?(s)
      assert s.comment_policy["required_groups"] == ["qa"]
      assert s.name == "upd"

      assert {:error, :invalid_origin} =
               Sites.update_site_security(site, %{"allowed_origins" => ["https://x/"]})

      assert {:error, :invalid_policy} =
               Sites.update_site_security(site, %{
                 "comment_policy" => %{"trust_host_roles" => "yes"}
               })
    end

    test "rotate_service_key replaces hash + seal", %{site: site} do
      assert {:ok, s, key} = Sites.rotate_service_key(site)
      assert s.service_key_hash == Annotate.Auth.ServiceKey.hash(key)
      refute s.service_key_hash == site.service_key_hash
    end
  end
end
