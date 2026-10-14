defmodule Annotate.Repo do
  use Ecto.Repo,
    otp_app: :annotate,
    adapter: Ecto.Adapters.Postgres
end
