defmodule Annotate.Schema.Annotate.WaitlistSignup do
  @moduledoc """
  One landing-page waitlist signup. Two shapes share the table: the landing
  "for you" form (interest `waitlist`, `about`/`use_case` filled — feedback
  a90465e3) and the dashboard plan/agent waitlists (interest `plan-*` /
  `agent-addon`, unique per pair).
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "waitlist_signups" do
    field :email, :string
    field :interest, :string
    field :about, :string
    field :use_case, :string
    field :source, :string, default: "landing"
    field :created_at, :utc_datetime_usec
  end
end
