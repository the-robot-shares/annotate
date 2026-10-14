defmodule Annotate.Auth.Providers do
  alias Annotate.Auth.Providers.Provider, as: Entity
  alias Annotate.Schema.Auth.Providers.Provider, as: Schema
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

  # <REMOVED UUID HERE> get_auth_provider :: auto-generated pointer for public function get_auth_provider
  def get_auth_provider(id, context, options \\ []), do: get(id, context, options)

  # <REMOVED UUID HERE> create :: auto-generated pointer for public function create
  # `super`, not `create` — a self-call lands back in this same clause and
  # change/2's `Enum.map(attrs, ...)` crashes on the non-enumerable it is
  # handed (Protocol.UndefinedError). A pre-built entity or changeset — what
  # `EntityRepo.create/2` dispatches here — skips change/2 entirely.
  def create(auth_provider, context, options \\ [])

  def create(%Entity{} = auth_provider, context, options),
    do: super(auth_provider, context, options)

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
  def update(%Entity{} = auth_provider, attrs, context, options) do
    auth_provider
    |> change(attrs)
    |> update(context, options)
  end

  # <REMOVED UUID HERE> delete :: auto-generated pointer for public function delete
  def delete(%Entity{} = auth_provider, context, options \\ []) do
    # A bare `delete(auth_provider, context, options)` is this very clause — unbounded
    # recursion. `super` reaches the def_repo-generated delete/3.
    super(auth_provider, context, options)
  end

  # <REMOVED UUID HERE> change :: auto-generated pointer for public function change
  def change(%Entity{} = auth_provider, attrs \\ %{}) do
    attrs =
      Enum.map(attrs, fn
        {"title", value} -> {:title, value}
        {"description", value} -> {:description, value}
        {"settings", value} -> {:settings, value}
        {"id", value} -> {:id, value}
        {k, v} when is_atom(k) -> {k, v}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    Ecto.Changeset.change(
      {auth_provider, Noizu.Entity.Meta.meta(Entity)[:changeset_fields]},
      attrs
    )
  end

  # <REMOVED UUID HERE> login :: auto-generated pointer for public function login
  def login() do
    Entity.ref(UUID.uuid5(:oid, "Annotate.Schema.Auth.Providers.Provider@Login"))
  end

  # <REMOVED UUID HERE> smart_token :: auto-generated pointer for public function smart_token
  def smart_token() do
    Entity.ref(UUID.uuid5(:oid, "Annotate.Schema.Auth.Providers.Provider@SmartToken"))
  end

  # <REMOVED UUID HERE> oidc :: auto-generated pointer for public function oidc
  def oidc() do
    Entity.ref(UUID.uuid5(:oid, "Annotate.Schema.Auth.Providers.Provider@OIDC"))
  end

  # <REMOVED UUID HERE> saml :: auto-generated pointer for public function saml
  def saml() do
    Entity.ref(UUID.uuid5(:oid, "Annotate.Schema.Auth.Providers.Provider@SAML"))
  end

  # <REMOVED UUID HERE> google :: auto-generated pointer for public function google
  def google() do
    Entity.ref(UUID.uuid5(:oid, "Annotate.Schema.Auth.Providers.Provider@Google"))
  end

  # <REMOVED UUID HERE> facebook :: auto-generated pointer for public function facebook
  def facebook() do
    Entity.ref(UUID.uuid5(:oid, "Annotate.Schema.Auth.Providers.Provider@Facebook"))
  end

  # <REMOVED UUID HERE> github :: auto-generated pointer for public function github
  def github() do
    Entity.ref(UUID.uuid5(:oid, "Annotate.Schema.Auth.Providers.Provider@GitHub"))
  end

  # <REMOVED UUID HERE> linkedin :: auto-generated pointer for public function linkedin
  def linkedin() do
    Entity.ref(UUID.uuid5(:oid, "Annotate.Schema.Auth.Providers.Provider@LinkedIn"))
  end
end
