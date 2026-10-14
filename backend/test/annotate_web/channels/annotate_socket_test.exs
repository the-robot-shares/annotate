defmodule AnnotateWeb.AnnotateSocketTest do
  @moduledoc """
  Socket-level tests for the annotate realtime endpoint: `check_origin/1`
  (transport MFA), `connect/3` (site resolution, origin binding, token
  authenticity), and `id/1`.

  The join AUTHORIZATION matrix lives here too (it is exercised through
  `AnnotateWeb.PageChannel` joins on the socket's `page:*` topics).
  """

  use AnnotateWeb.ChannelCase, async: true

  alias Annotate.Realtime

  @good "https://good.example"
  @evil "https://evil.example"
  @other "https://other.example"

  # ── check_origin (transport MFA) ──────────────────────────────

  describe "check_origin/1" do
    test "allows an origin in a site's allowed_origins" do
      {site, _key} = create_site()
      assert @good in site.allowed_origins
      assert AnnotateWeb.AnnotateSocket.check_origin(URI.parse(@good))
    end

    test "rejects an origin not in any site's allowed_origins" do
      {site, _key} = create_site()
      refute @evil in site.allowed_origins
      refute AnnotateWeb.AnnotateSocket.check_origin(URI.parse(@evil))
    end

    test "rejects malformed origins" do
      refute AnnotateWeb.AnnotateSocket.check_origin(URI.parse("not-a-uri"))
      # host-only (no scheme) parses to host: "ftp.example"
      refute AnnotateWeb.AnnotateSocket.check_origin(URI.parse("ftp://good.example"))
    end

    test "keeps non-default ports in the origin identity" do
      {_site, _key} = create_site(origins: ["https://good.example:8443"])
      assert AnnotateWeb.AnnotateSocket.check_origin(URI.parse("https://good.example:8443"))
      refute AnnotateWeb.AnnotateSocket.check_origin(URI.parse("https://good.example"))
    end
  end

  # ── connect ───────────────────────────────────────────────────

  describe "connect/3" do
    test "connects anonymously to a known site" do
      {site, _key} = create_site()
      assert {:ok, socket} = connect(AnnotateWeb.AnnotateSocket, %{"site" => site.slug})
      assert socket.assigns.site.id == site.id
      assert is_nil(socket.assigns.claims)
      assert is_nil(AnnotateWeb.AnnotateSocket.id(socket))
    end

    test "connects with a valid token and tracks the commenter id" do
      {site, _key} = create_site()
      commenter = create_commenter()
      token = issue_access(commenter, site, @good)

      assert {:ok, socket} =
               connect(AnnotateWeb.AnnotateSocket, %{"site" => site.slug, "token" => token})

      assert socket.assigns.claims["sub"] == commenter.id
      assert AnnotateWeb.AnnotateSocket.id(socket) == "annotate_socket:#{commenter.id}"
    end

    test "refuses an unknown site" do
      assert {:error, %{reason: "site_not_found"}} =
               connect(AnnotateWeb.AnnotateSocket, %{"site" => "nope"})
    end

    test "refuses a presented-but-invalid token (never falls back to anonymous)" do
      {site, _key} = create_site(settings: %{"public_read" => true})

      assert {:error, %{reason: "invalid_token"}} =
               connect(AnnotateWeb.AnnotateSocket, %{"site" => site.slug, "token" => "garbage"})
    end

    test "per-site origin binding: an origin registered to ANOTHER site cannot connect as this site" do
      # The transport MFA (check_origin/1) runs first in the handshake
      # process and stashes the validated origin; connect/3 then requires it
      # to be allowed for the site named in the connect params.
      {site_a, _} = create_site(origins: [@good])
      create_site(origins: [@other])

      # Handshake for @other succeeds the registry-wide gate…
      assert AnnotateWeb.AnnotateSocket.check_origin(URI.parse(@other))
      # …but binding it to site_a (which only allows @good) is refused.
      assert {:error, %{reason: "origin_not_allowed"}} =
               connect(AnnotateWeb.AnnotateSocket, %{"site" => site_a.slug})
    end
  end

  # ── join authorization (through PageChannel) ──────────────────

  describe "join/3 authorization" do
    test "anonymous join allowed when public_read is true" do
      {site, _key} = create_site(settings: %{"public_read" => true})

      assert {:ok, _reply, _socket} =
               subscribe_and_join_socket(site, "/page/#{page_suffix()}")
    end

    test "join allowed with a valid token whose site and origin claims match" do
      {site, _key} = create_site(settings: %{"public_read" => false})
      commenter = create_commenter()
      token = issue_access(commenter, site, @good)

      assert {:ok, _reply, _socket} =
               subscribe_and_join_socket(site, "/page/#{page_suffix()}", %{"token" => token})
    end

    test "join denied on a non-public site without a token" do
      {site, _key} = create_site(settings: %{"public_read" => false})

      assert {:error, %{reason: "invalid_token"}} =
               subscribe_and_join_socket(site, "/page/#{page_suffix()}")
    end

    test "join denied on a non-public site with a bad token (connect refuses it)" do
      {site, _key} = create_site(settings: %{"public_read" => false})

      assert {:error, %{reason: "invalid_token"}} =
               subscribe_and_join_socket(site, "/page/#{page_suffix()}", %{
                 "token" => "bad.token.here"
               })
    end

    test "join denied when the token's site claim points at another site" do
      {site_a, _} = create_site(settings: %{"public_read" => false}, origins: [@good])
      {site_b, _} = create_site(origins: [@good])
      commenter = create_commenter()
      # Minted for site_b, presented on a socket for site_a.
      token = issue_access(commenter, site_b, @good)

      assert {:error, %{reason: "site_mismatch"}} =
               subscribe_and_join_socket(site_a, "/page/#{page_suffix()}", %{"token" => token})
    end

    test "join denied when the token's origin claim is not one of the site's allowed_origins" do
      {site, _key} = create_site(settings: %{"public_read" => false})
      commenter = create_commenter()
      token = issue_access(commenter, site, @evil)

      assert {:error, %{reason: "origin_mismatch"}} =
               subscribe_and_join_socket(site, "/page/#{page_suffix()}", %{"token" => token})
    end

    test "a presented token with a bad origin claim is denied even on a public site" do
      {site, _key} = create_site(settings: %{"public_read" => true})
      commenter = create_commenter()
      token = issue_access(commenter, site, @evil)

      assert {:error, %{reason: "origin_mismatch"}} =
               subscribe_and_join_socket(site, "/page/#{page_suffix()}", %{"token" => token})
    end
  end

  describe "join/3 topic validation" do
    test "topic must name the socket's own site" do
      {site_a, _} = create_site(settings: %{"public_read" => true})
      {site_b, _} = create_site(settings: %{"public_read" => true})
      foreign_topic = Realtime.page_topic(site_b.slug, "/x")

      assert {:ok, socket} = connect(AnnotateWeb.AnnotateSocket, %{"site" => site_a.slug})

      assert {:error, %{reason: "site_mismatch"}} =
               subscribe_and_join(socket, AnnotateWeb.PageChannel, foreign_topic)
    end

    test "topic hash must be 64 lowercase hex chars" do
      {site, _key} = create_site(settings: %{"public_read" => true})
      assert {:ok, socket} = connect(AnnotateWeb.AnnotateSocket, %{"site" => site.slug})

      assert {:error, %{reason: "invalid_page_hash"}} =
               subscribe_and_join(socket, AnnotateWeb.PageChannel, "page:#{site.slug}:NOTAHASH")

      assert {:error, %{reason: "invalid_page_hash"}} =
               subscribe_and_join(
                 socket,
                 AnnotateWeb.PageChannel,
                 "page:#{site.slug}:" <> String.upcase(Realtime.page_hash("/x"))
               )
    end

    test "malformed topics are rejected" do
      {site, _key} = create_site(settings: %{"public_read" => true})
      assert {:ok, socket} = connect(AnnotateWeb.AnnotateSocket, %{"site" => site.slug})

      assert {:error, %{reason: "invalid_topic"}} =
               subscribe_and_join(socket, AnnotateWeb.PageChannel, "page:#{site.slug}")
    end
  end

  # ── Helpers ───────────────────────────────────────────────────

  defp page_suffix, do: "rt-#{System.unique_integer([:positive])}"

  defp subscribe_and_join_socket(site, page_key, connect_params \\ %{}) do
    with {:ok, socket} <-
           connect(
             AnnotateWeb.AnnotateSocket,
             Map.merge(%{"site" => site.slug}, connect_params)
           ) do
      subscribe_and_join(
        socket,
        AnnotateWeb.PageChannel,
        Realtime.page_topic(site.slug, page_key)
      )
    end
  end
end
