defmodule Annotate.Schema.Annotate.Page do
  @moduledoc "A host page (site + page_key) that carries comment threads."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "pages" do
    belongs_to :site, Annotate.Schema.Annotate.Site, type: Ecto.UUID
    field :page_key, :string
    field :last_url, :string
    field :title, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:site_id, :page_key, :last_url, :title])
    |> validate_required([:site_id, :page_key])
    |> unique_constraint([:site_id, :page_key], name: :pages_site_page_key)
  end
end
