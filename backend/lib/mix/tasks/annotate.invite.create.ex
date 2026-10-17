defmodule Mix.Tasks.Annotate.Invite.Create do
  @moduledoc """
  Issues one dashboard invite and prints its sign-up link ONCE.

      mix annotate.invite.create [--email someone@example.com] [--days 14] [--max-uses 1]

  In a release use `Annotate.Release.issue_invite/1`.
  """

  use Mix.Task

  @shortdoc "Issue a dashboard invite link (printed once)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, invalid} =
      OptionParser.parse(args, strict: [email: :string, days: :integer, max_uses: :integer])

    unless invalid == [], do: Mix.raise("Unknown options: #{inspect(invalid)}")

    case Annotate.Dashboard.Invites.create(nil, opts) do
      {:ok, invite, raw} ->
        Mix.shell().info("invite #{invite.key_prefix}… expires #{invite.expires_at}")
        Mix.shell().info(Annotate.Dashboard.Invites.link(raw))

      {:error, reason} ->
        Mix.raise("Invite failed: #{inspect(reason)}")
    end
  end
end
