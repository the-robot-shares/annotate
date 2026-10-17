defmodule Mix.Tasks.Annotate.Site.Grant do
  @moduledoc """
  Grants OWNER on a site to a verified dashboard user (idempotent).

      mix annotate.site.grant --slug my-site --email owner@example.com

  The user must have signed in to the dashboard once (GitHub) so the
  verified user row exists. In a release use
  `Annotate.Release.grant_site_owner/2`.
  """

  use Mix.Task

  @shortdoc "Grant site ownership to a verified dashboard user"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _args, invalid} = OptionParser.parse(args, strict: [slug: :string, email: :string])

    unless invalid == [], do: Mix.raise("Unknown options: #{inspect(invalid)}")

    slug = opts[:slug] || Mix.raise("--slug is required")
    email = opts[:email] || Mix.raise("--email is required")

    case Annotate.SiteMembers.grant_owner_by_email(slug, email) do
      :ok -> Mix.shell().info("Owner granted on #{slug}.")
      {:error, reason} -> Mix.raise("Grant failed: #{reason}")
    end
  end
end
