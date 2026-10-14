defmodule Annotate.Users.Media do
  alias Annotate.Users.Media.Asset, as: Entity
  alias Annotate.Schema.Users.Media.Asset, as: Schema
  use Noizu.Repo
  def_repo(entity: Entity)

  # <REMOVED UUID HERE> list :: auto-generated pointer for public function list
  def list(context, options \\ []) do
    settings = Noizu.Entity.Meta.persistence(Entity) |> hd

    Annotate.Repo.all(Schema)
    |> Enum.map(fn record ->
      {:ok, entity} = Entity.from_record(record, settings, context, options)
      {:ok, entity} = __after_get__(entity, context, options)
      entity
    end)
  end

  # <REMOVED UUID HERE> list_for_user :: auto-generated pointer for public function list_for_user
  def list_for_user(user_id, context, options \\ []) do
    import Ecto.Query
    settings = Noizu.Entity.Meta.persistence(Entity) |> hd

    Annotate.Repo.all(from m in Schema, where: m.user_id == ^user_id)
    |> Enum.map(fn record ->
      {:ok, entity} = Entity.from_record(record, settings, context, options)
      {:ok, entity} = __after_get__(entity, context, options)
      entity
    end)
  end

  # <REMOVED UUID HERE> get_user_media :: auto-generated pointer for public function get_user_media
  def get_user_media(id, context, options \\ []), do: get(id, context, options)

  # <REMOVED UUID HERE> create :: auto-generated pointer for public function create
  # `super`, not `create` — a self-call lands back in this same clause and
  # change/2's `Enum.map(attrs, ...)` crashes on the non-enumerable it is
  # handed (Protocol.UndefinedError). A pre-built entity or changeset — what
  # `EntityRepo.create/2` dispatches here — skips change/2 entirely.
  def create(user_media, context, options \\ [])

  def create(%Entity{} = user_media, context, options), do: super(user_media, context, options)

  def create(%Ecto.Changeset{} = changeset, context, options),
    do: super(changeset, context, options)

  def create(attrs, context, options) do
    %Entity{}
    |> change(attrs)
    |> super(context, options)
  end

  # <REMOVED UUID HERE> update :: auto-generated pointer for public function update
  # Arity 4 only — an `options \\ []` default would also define update/3 and
  # shadow the def_repo-generated update/3 that this body calls.
  def update(%Entity{} = user_media, attrs, context, options) do
    user_media
    |> change(attrs)
    |> update(context, options)
  end

  # <REMOVED UUID HERE> delete :: auto-generated pointer for public function delete
  def delete(%Entity{} = user_media, context, options \\ []) do
    # A bare `delete(user_media, context, options)` is this very clause — unbounded
    # recursion. `super` reaches the def_repo-generated delete/3.
    super(user_media, context, options)
  end

  # <REMOVED UUID HERE> change :: auto-generated pointer for public function change
  def change(%Entity{} = user_media, attrs \\ %{}) do
    attrs =
      Enum.map(attrs, fn
        {"user_id", value} -> {:user, value}
        {"media_id", value} -> {:media, value}
        {"description_id", value} -> {:description, value}
        {"media_type", value} -> {:media_type, String.to_existing_atom(value)}
        {"settings", value} -> {:settings, value}
        {"id", value} -> {:id, value}
        {k, v} when is_atom(k) -> {k, v}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    Ecto.Changeset.change({user_media, Noizu.Entity.Meta.meta(Entity)[:changeset_fields]}, attrs)
  end
end
