defmodule Annotate.Entities.RepoOverrideDispatchTest do
  # Regression: the scaffold shipped create/update/delete overrides in the six
  # def_repo modules below that dispatched back into themselves instead of
  # `super`:
  #   * create/3 piped a built entity into change/2 → Protocol.UndefinedError
  #     (EntityRepo.create/2 hands it a built entity, so Credentials.register/4 —
  #     email/password sign-up — raised on its first Versioned.Strings create);
  #   * update/4's `options \\ []` default also defined update/3, shadowing the
  #     def_repo update/3 the body calls → FunctionClauseError on the changeset;
  #   * delete/3 called itself → unbounded recursion.
  # Every call runs in a bounded task so the recursion fails fast instead of
  # hanging the suite.
  use Annotate.DataCase, async: false

  alias Annotate.Auth.Providers
  alias Annotate.Media
  alias Annotate.Users.Media, as: UserMedia
  alias Annotate.Versioned.Descriptions
  alias Annotate.Versioned.Names
  alias Annotate.Versioned.Strings

  @timeout 5_000

  setup do
    {:ok, context: Noizu.Context.system()}
  end

  defp bounded(fun) do
    task =
      Task.async(fn ->
        try do
          fun.()
        rescue
          e -> {:raised, e}
        end
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> :timeout
    end
  end

  defp now, do: Noizu.Entity.TimeStamp.now()

  # Exercises create (built entity, changeset, attrs), update/4, the generated
  # update/3 and delete/3 on one repo module.
  defp assert_crud(repo, entity_mod, built, attrs, update_attrs, context) do
    assert {:ok, %^entity_mod{id: id} = created} = bounded(fn -> repo.create(built, context) end)
    assert id

    assert {:ok, %^entity_mod{}} =
             bounded(fn -> Annotate.EntityRepo.create(%{built | id: nil}, context) end)

    assert {:ok, %^entity_mod{}} =
             bounded(fn -> repo.create(repo.change(struct(entity_mod), attrs), context, []) end)

    assert {:ok, %^entity_mod{}} = bounded(fn -> repo.create(attrs, context) end)

    assert {:ok, %^entity_mod{} = updated} =
             bounded(fn -> repo.update(created, update_attrs, context, []) end)

    for {k, v} <- update_attrs, do: assert(Map.get(updated, k) == v)

    assert {:ok, %^entity_mod{}} =
             bounded(fn -> repo.update(repo.change(updated, %{}), context, []) end)

    assert {:ok, _} = bounded(fn -> repo.delete(updated, context) end)
  end

  test "Versioned.Strings create/update/delete dispatch to the def_repo defaults", %{
    context: context
  } do
    assert_crud(
      Strings,
      Strings.String,
      %Strings.String{content: "hello", time_stamp: now()},
      %{content: "from attrs"},
      %{content: "updated"},
      context
    )
  end

  test "Versioned.Names create/update/delete dispatch to the def_repo defaults", %{
    context: context
  } do
    assert_crud(
      Names,
      Names.Name,
      %Names.Name{first: "Ada", middle: [], last: "Lovelace", time_stamp: now()},
      %{first: "Grace", last: "Hopper"},
      %{first: "Updated"},
      context
    )
  end

  test "Versioned.Descriptions create/update/delete dispatch to the def_repo defaults", %{
    context: context
  } do
    assert_crud(
      Descriptions,
      Descriptions.Description,
      %Descriptions.Description{title: "Title", body: "Body", time_stamp: now()},
      %{title: "Attrs", body: "Attrs body"},
      %{body: "Updated"},
      context
    )
  end

  test "Auth.Providers create/update/delete dispatch to the def_repo defaults", %{
    context: context
  } do
    assert_crud(
      Providers,
      Providers.Provider,
      %Providers.Provider{
        title: "Dispatch #{System.unique_integer([:positive])}",
        description: "regression",
        settings: %{},
        time_stamp: now()
      },
      %{title: "Attrs provider", description: "attrs"},
      %{description: "Updated"},
      context
    )
  end

  test "Media create/update/delete dispatch to the def_repo defaults", %{context: context} do
    assert_crud(
      Media,
      Media.Asset,
      %Media.Asset{
        media_type: :image,
        file_type: :png,
        file: "dispatch.png",
        visibility: "private",
        flagged: false,
        settings: %{},
        time_stamp: now()
      },
      %{media_type: :image, file_type: :jpg, file: "attrs.jpg"},
      # short_id is DB-defaulted on insert but the entity copy stays nil, so an
      # update must carry it or it writes NULL into a NOT NULL column.
      %{file: "updated.png", short_id: "dsp#{System.unique_integer([:positive])}"},
      context
    )
  end

  # media_type now matches the DB's media_type_enum (image/video/audio/document/
  # other); :image exercises a value the pre-fix Ecto.Enum rejected.
  test "Users.Media create/update/delete dispatch to the def_repo defaults", %{
    context: context
  } do
    user = register_user!(context)
    {:ok, user_ref} = Noizu.EntityReference.Protocol.ref(user)

    {:ok, media} =
      Media.create(
        %Media.Asset{media_type: :image, file_type: :png, file: "u.png", time_stamp: now()},
        context
      )

    {:ok, description} =
      Descriptions.create(
        %Descriptions.Description{title: "t", body: "b", time_stamp: now()},
        context
      )

    {:ok, media_ref} = Noizu.EntityReference.Protocol.ref(media)
    {:ok, description_ref} = Noizu.EntityReference.Protocol.ref(description)

    assert_crud(
      UserMedia,
      UserMedia.Asset,
      %UserMedia.Asset{
        user: user_ref,
        media: media_ref,
        description: description_ref,
        media_type: :image,
        settings: %{},
        time_stamp: now()
      },
      %{user: user_ref, media: media_ref, description: description_ref, media_type: :image},
      %{settings: %{"k" => "v"}},
      context
    )
  end

  test "Credentials.register/4 (email/password sign-up) creates the credential", %{
    context: context
  } do
    user = register_user!(context)
    email = "dispatch-cred-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, %Annotate.Users.Credentials.UserCredential{id: id}} =
             bounded(fn ->
               Annotate.Users.Credentials.register(
                 user,
                 {:login, {email, "Password123!"}},
                 context,
                 []
               )
             end)

    assert id
  end

  defp register_user!(context) do
    n = System.unique_integer([:positive])

    {:ok, {user, _credential}} =
      Annotate.Users.register(
        %{
          name: %{first: "Dispatch", last: "Test"},
          user_name: "dispatch#{n}",
          handle: "dispatch-#{n}"
        },
        {:login, {"dispatch-#{n}@example.com", "Password123!"}},
        context
      )

    {:ok, entity} = Annotate.Users.get_user(user.id, context)
    entity
  end
end
