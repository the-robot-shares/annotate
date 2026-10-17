defmodule Annotate.Schema.Annotate.WaitlistSignup do
  @moduledoc "One landing-page waitlist signup: an email and one interest (unique pair)."
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "waitlist_signups" do
    field :email, :string
    field :interest, :string
    field :source, :string, default: "landing"
    field :created_at, :utc_datetime_usec
  end
end
