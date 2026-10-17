# DEV-ONLY (scripts/devbox). The whole module is compiled out unless
# Mix.env() == :dev, and the router scope that points at it is behind the same
# guard — prod/test builds contain neither (test/.../dev_login_test.exs pins this).
if Mix.env() == :dev do
  defmodule AnnotateWeb.AnnotateAPI.DevLoginController do
    @moduledoc """
    "Log in as" for the local devbox: stands in for the Authentik popup broker.

    - `GET  /embed/dev-login?site=<slug>&origin=<origin>` — name + email form.
    - `POST /embed/dev-login` — upserts a dev commenter (external id
      `dev:<email>`), mints the same token pair `/embed/callback` would, and
      renders the same postMessage page to the registered origin.

    The origin must be in the site's `allowed_origins` (exact match), exactly as
    the real broker. Writes a commenter + refresh-token row, so against cluster
    data it needs `DEVBOX_CLUSTER_WRITES=1` (and should only be used with the
    dedicated `devbox` site).
    """
    use AnnotateWeb, :controller

    alias Annotate.Auth.ApiToken
    alias Annotate.Sites

    def form(conn, %{"site" => slug, "origin" => origin}) do
      case check(slug, origin) do
        {:ok, _site} -> html(conn, form_page(slug, origin, ""))
        {:error, reason} -> conn |> put_status(:bad_request) |> text(reason)
      end
    end

    def form(conn, _), do: conn |> put_status(:bad_request) |> text("site and origin required")

    def login(conn, %{"site" => slug, "origin" => origin, "email" => email} = params) do
      name = String.trim(params["name"] || "")
      email = String.trim(email)

      with {:ok, site} <- check(slug, origin),
           true <-
             (name != "" and String.contains?(email, "@")) ||
               {:error, "name and a valid email are required"},
           claims = %{"name" => name, "email" => email, "sub" => "dev:" <> String.downcase(email)},
           {:ok, commenter} <- Sites.upsert_commenter_by_external(site, claims["sub"], claims),
           {:ok, %{access_token: access, refresh_token: refresh}} <-
             ApiToken.issue_pair(commenter, site, origin, %{}, :none) do
        payload = %{
          "type" => "annotate-auth",
          "access" => access,
          "refresh" => refresh,
          "commenter" => commenter.id,
          "display_name" => commenter.display_name
        }

        html(conn, postmessage_page(Jason.encode!(payload), origin))
      else
        {:error, reason} when is_binary(reason) ->
          conn |> put_status(:bad_request) |> html(form_page(slug, origin, reason))

        other ->
          conn |> put_status(:unprocessable_entity) |> text("dev login failed: #{inspect(other)}")
      end
    end

    def login(conn, _),
      do: conn |> put_status(:bad_request) |> text("site, origin, name, email required")

    defp check(slug, origin) do
      case Sites.get_site_by_slug(slug) do
        nil ->
          {:error, "unknown site"}

        site ->
          if Sites.allowed_origin?(site, origin),
            do: {:ok, site},
            else: {:error, "origin not allowed for site"}
      end
    end

    defp esc(v), do: v |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    defp form_page(slug, origin, error) do
      """
      <!doctype html><html><body style="font-family:system-ui,sans-serif;max-width:24rem;margin:3rem auto">
      <h1 style="font-size:1.1rem">Devbox: log in as</h1>
      <p style="color:#a00">#{esc(error)}</p>
      <form method="post" action="/embed/dev-login">
        <input type="hidden" name="site" value="#{esc(slug)}">
        <input type="hidden" name="origin" value="#{esc(origin)}">
        <p><label>Display name<br><input name="name" value="Dev User" required></label></p>
        <p><label>Email<br><input name="email" type="email" value="dev@example.test" required></label></p>
        <button type="submit">Sign in</button>
      </form></body></html>
      """
    end

    defp postmessage_page(encoded_payload, origin) do
      """
      <!doctype html><html><body style="font-family:system-ui,sans-serif;padding:2rem;text-align:center">
      <p id="msg">Signing you in&hellip;</p>
      <script>
      (function(){
        var payload = #{encoded_payload};
        var origin = #{Jason.encode!(origin)};
        var sent = false;
        if (window.opener) { window.opener.postMessage(payload, origin); sent = true; }
        document.getElementById("msg").textContent = sent ? "Signed in - you can close this window." : "No opener window; close this tab.";
        window.close();
      })();
      </script></body></html>
      """
    end
  end
end
