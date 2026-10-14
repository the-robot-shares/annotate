defmodule Starter.Users.Sessions do
  @moduledoc """
  Context for Starter.Users.Sessions
  """
  alias Starter.Users.Sessions.UserSession, as: Entity
  alias Starter.Schema.Users.Sessions.UserSession, as: Schema
  use Noizu.Repo
  def_repo(entity: Starter.Users.Sessions.UserSession)

  # <REMOVED UUID HERE> list :: auto-generated pointer for public function list
  def list(context, options \\ []) do
    settings = Noizu.Entity.Meta.persistence(Entity) |> hd

    Starter.Repo.all(Schema)
    |> Enum.map(fn record ->
      {:ok, entity} = Entity.from_record(record, settings, context, options)
      {:ok, entity} = __after_get__(entity, context, options)
      entity
    end)
  end

  # <REMOVED UUID HERE> get_session :: auto-generated pointer for public function get_session
  def get_session(id, context, options \\ []), do: get(id, context, options)

  # <REMOVED UUID HERE> create :: auto-generated pointer for public function create
  def create(session, context, options \\ [])

  def create(%Entity{} = session, context, options) do
    super(session, context, options)
  end

  def create(session, context, options) do
    %Entity{}
    |> change(session)
    |> super(context, options)
  end

  # <REMOVED UUID HERE> delete :: auto-generated pointer for public function delete
  def delete(session, context, options \\ []) do
    super(session, context, options)
  end

  # <REMOVED UUID HERE> change :: auto-generated pointer for public function change
  def change(%Entity{} = session, attrs \\ %{}) do
    attrs =
      Enum.map(
        attrs,
        fn
          {"user", value} -> {:user, value}
          {"credential", value} -> {:credential, value}
          {"status", value} -> {:status, String.to_existing_atom(value)}
          {"details", value} -> {:details, value}
          {"id", value} -> {:id, value}
          {x, value} when is_atom(x) -> {x, value}
          _ -> nil
        end
      )
      |> Enum.reject(&is_nil/1)

    Ecto.Changeset.change(
      {session, Noizu.Entity.Meta.meta(Entity)[:changeset_fields]},
      attrs
    )
  end
end
