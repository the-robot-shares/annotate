defmodule Annotate.Schema.Annotate.Attachment do
  @moduledoc """
  An uploaded attachment (file, image, or screenshot).

  Lifecycle: `pending` (presigned PUT issued, object not yet confirmed) →
  `ready` (`POST /api/v1/attachments/:id/complete`). `pending` rows older
  than 24h are swept by `Annotate.Workers.AttachmentSweeper`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "attachments" do
    belongs_to :comment, Annotate.Schema.Annotate.Comment, type: Ecto.UUID
    belongs_to :uploader, Annotate.Schema.Annotate.Commenter, type: Ecto.UUID
    belongs_to :site, Annotate.Schema.Annotate.Site, type: Ecto.UUID
    field :kind, Ecto.Enum, values: [:file, :image, :screenshot], default: :file
    field :storage_key, :string
    field :content_type, :string
    field :bytes, :integer
    field :width, :integer
    field :height, :integer
    field :annotation, :map
    field :status, Ecto.Enum, values: [:pending, :ready], default: :pending

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [
      :comment_id,
      :uploader_id,
      :site_id,
      :kind,
      :storage_key,
      :content_type,
      :bytes,
      :width,
      :height,
      :annotation,
      :status
    ])
    |> validate_required([:uploader_id, :site_id, :storage_key])
    |> foreign_key_constraint(:comment_id)
  end
end
