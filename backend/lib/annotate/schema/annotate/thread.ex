defmodule Annotate.Schema.Annotate.Thread do
  @moduledoc """
  A comment thread anchored to a position on a page.

  `anchor` is an opaque jsonb blob produced by the host-site widget (element
  path / coordinates). When a page layout changes and the anchor no longer
  resolves, the widget sets `orphaned_at`; `PATCH /api/v1/threads/:id/anchor`
  repairs it and clears the flag.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "threads" do
    belongs_to :page, Annotate.Schema.Annotate.Page, type: Ecto.UUID
    field :anchor, :map
    field :status, Ecto.Enum, values: [:open, :resolved], default: :open
    has_many :comments, Annotate.Schema.Annotate.Comment, foreign_key: :thread_id
    # DDL columns are created_by / resolved_by (no _id suffix); the scaffold
    # convention names the assoc off the FK (cf. projects/project.ex).
    belongs_to :creator, Annotate.Schema.Annotate.Commenter,
      type: Ecto.UUID,
      foreign_key: :created_by

    belongs_to :resolver, Annotate.Schema.Annotate.Commenter,
      type: Ecto.UUID,
      foreign_key: :resolved_by

    field :resolved_at, :utc_datetime_usec
    field :orphaned_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [
      :page_id,
      :anchor,
      :status,
      :created_by,
      :resolved_by,
      :resolved_at,
      :orphaned_at
    ])
    |> validate_required([:page_id, :anchor])
    |> foreign_key_constraint(:page_id)
  end
end
