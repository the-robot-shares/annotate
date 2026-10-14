defmodule Annotate.Schema.Annotate.Comment do
  @moduledoc """
  A comment within a thread (root comment when `parent_id` is nil).

  Deletion is soft (`deleted_at`); deleted comments are excluded from thread
  reads. `author_id` is nullable — anonymous/guest comments carry no author
  and may only be deleted by the site owner.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "comments" do
    belongs_to :thread, Annotate.Schema.Annotate.Thread, type: Ecto.UUID
    belongs_to :parent, Annotate.Schema.Annotate.Comment, type: Ecto.UUID
    belongs_to :author, Annotate.Schema.Annotate.Commenter, type: Ecto.UUID

    has_many :attachments, Annotate.Schema.Annotate.Attachment, foreign_key: :comment_id
    field :body_md, :string, default: ""
    field :edited_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:thread_id, :parent_id, :author_id, :body_md, :edited_at, :deleted_at])
    |> validate_required([:thread_id])
    |> validate_length(:body_md, max: 20_000)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:parent_id)
  end
end
