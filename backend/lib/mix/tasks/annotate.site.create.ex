defmodule Mix.Tasks.Annotate.Site.Create do
  @moduledoc """
  Creates an annotate site and prints its generated service key ONCE.

      mix annotate.site.create --slug my-site --name "My Site" --origins https://a.example,https://b.example

  The service key is shown exactly once here — the database stores only its
  sha256 hash and the AES-sealed value (see `Annotate.Auth.ServiceKey`). Give
  it to the host site's backend so it can sign host-asserted identity JWTs.
  """

  use Mix.Task

  alias Annotate.Sites

  @shortdoc "Create an annotate site (prints the service key once)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _args, invalid} =
      OptionParser.parse(args, strict: [slug: :string, name: :string, origins: :string])

    unless invalid == [] do
      Mix.raise("Unknown options: #{inspect(invalid)}")
    end

    slug = opts[:slug] || Mix.raise("--slug is required")
    name = opts[:name] || Mix.raise("--name is required")

    origins =
      case opts[:origins] do
        nil -> []
        list -> list |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      end

    case Sites.create_site(%{
           "slug" => slug,
           "name" => name,
           "allowed_origins" => origins
         }) do
      {:ok, site, service_key} ->
        Mix.shell().info("Site created: #{site.slug} (#{site.id})")
        Mix.shell().info("Allowed origins: #{Enum.join(origins, ", ")}")
        Mix.shell().info("")
        Mix.shell().info("Service key (shown ONCE — store it now):")
        Mix.shell().info(service_key)

      {:error, changeset} ->
        Mix.raise(
          "Site creation failed: #{inspect(Ecto.Changeset.traverse_errors(changeset, & &1))}"
        )
    end
  end
end
