defmodule Annotate.Release do
  @moduledoc """
  Schema migrations are handled by Liquibase (see backend/db/).
  This module provides seed running for releases.
  """
  @app :annotate

  # <REMOVED UUID HERE> migrate :: auto-generated pointer for public function migrate
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  # <REMOVED UUID HERE> rollback :: auto-generated pointer for public function rollback
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # <REMOVED UUID HERE> seed :: auto-generated pointer for public function seed
  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          Code.eval_file(Path.join([:code.priv_dir(@app), "repo", "seeds.exs"]))
        end)
    end
  end

  @doc """
  Ops seed: grants OWNER on site `slug` to the verified dashboard user with
  `email` (they must have signed in once so the user row exists). Idempotent.

      bin/annotate eval 'Annotate.Release.grant_site_owner("demo", "someone@example.com")'

  Prints only the outcome (never config, keys or other users' data).
  """
  def grant_site_owner(slug, email) when is_binary(slug) and is_binary(email) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(Annotate.Repo, fn _repo ->
        Annotate.SiteMembers.grant_owner_by_email(slug, email)
      end)

    IO.puts("grant_site_owner #{slug}: #{inspect(result)}")
    result
  end

  @doc """
  Ops: issues ONE dashboard invite and prints its sign-up link once (the raw
  token is never stored). `opts`: `email:` (bind), `days:`, `max_uses:`.

      bin/annotate eval 'Annotate.Release.issue_invite(email: "someone@example.com")'
  """
  def issue_invite(opts \\ []) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(Annotate.Repo, fn _repo ->
        Annotate.Dashboard.Invites.create(nil, opts)
      end)

    case result do
      {:ok, invite, raw} ->
        IO.puts("invite #{invite.key_prefix}… expires #{invite.expires_at}")
        IO.puts(Annotate.Dashboard.Invites.link(raw))
        :ok

      {:error, reason} ->
        IO.puts("issue_invite failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
