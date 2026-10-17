defmodule Annotate.Schema.Annotate.Site do
  @moduledoc """
  A tenant of the annotate embeddable comments service.

  `settings` (jsonb): `%{"public_read" => true, "page_key_strategy" => "strip_query_hash",
  "max_upload_mb" => 20}` — read through the accessors on `Annotate.Sites`.

  `comment_policy` (jsonb): `%{"required_groups" => [], "allowed_email_domains" => [],
  "host_identity" => false}` — enforced by `Annotate.Embed.Policy`; empty = no constraint.

  `service_key_hash` is the sha256 of the site's service key (shown once at
  creation); `service_key_encrypted` is the key itself, AES-256-GCM sealed
  under ANNOTATE_KEY_ENC_SECRET (see `Annotate.Auth.ServiceKey`) so the
  host-assert flow (HMAC verification) can recover it without storing plaintext.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "sites" do
    field :slug, :string
    field :name, :string
    field :allowed_origins, {:array, :string}, default: []
    field :service_key_hash, :string
    field :service_key_encrypted, :string

    field :settings, :map,
      default: %{
        "public_read" => true,
        "page_key_strategy" => "strip_query_hash",
        "max_upload_mb" => 20
      }

    field :comment_policy, :map, default: %{}
    belongs_to :owner_commenter, Annotate.Schema.Annotate.Commenter, type: Ecto.UUID

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(site, attrs) do
    site
    |> cast(attrs, [
      :slug,
      :name,
      :allowed_origins,
      :service_key_hash,
      :service_key_encrypted,
      :settings,
      :comment_policy,
      :owner_commenter_id
    ])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> unique_constraint(:slug, name: :sites_slug_key)
  end
end
