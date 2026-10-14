defmodule Mix.Tasks.Liquibase.Update do
  use Mix.Task

  @shortdoc "Applies the canonical Liquibase schema to the configured Repo database"

  @impl Mix.Task
  # <REMOVED UUID HERE> run :: auto-generated pointer for public function run
  def run(args) do
    Mix.Task.run("app.config")

    quiet? = "--quiet" in args

    unless System.find_executable("liquibase") do
      Mix.raise("liquibase CLI is required to apply the canonical start-app schema")
    end

    repo_config = Application.fetch_env!(:annotate, Annotate.Repo)
    host = Keyword.get(repo_config, :hostname, "localhost")
    port = Keyword.get(repo_config, :port, 5432)
    database = Keyword.fetch!(repo_config, :database)
    username = Keyword.fetch!(repo_config, :username)
    password = Keyword.get(repo_config, :password, "")
    db_dir = Path.expand("../../../db", __DIR__)

    liquibase_args = [
      "--url=jdbc:postgresql://#{host}:#{port}/#{database}",
      "--username=#{username}",
      "--password=#{password}",
      "--changeLogFile=changelog/db.changelog-master.yaml",
      "update"
    ]

    {output, status} =
      System.cmd("liquibase", liquibase_args, cd: db_dir, stderr_to_stdout: true)

    if !quiet? or status != 0 do
      Mix.shell().info(output)
    end

    if status != 0 do
      Mix.raise("liquibase update failed with status #{status}")
    end
  end
end
