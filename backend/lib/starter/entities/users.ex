defmodule Starter.Users do
  @moduledoc """
  Context for Starter.Users
  """
  alias Starter.Users.User, as: Entity
  alias Starter.Schema.Auth.Providers.Provider, as: ProviderSchema
  alias Starter.Schema.Users.User, as: Schema
  alias Starter.Schema.Users.Credentials.UserCredential, as: CredentialSchema
  alias Starter.Schema.Versioned.Descriptions.Description, as: DescriptionSchema
  alias Starter.Schema.Versioned.Names.Name, as: NameSchema
  use Noizu.Repo
  def_repo(entity: Starter.Users.User)

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

  # <REMOVED UUID HERE> get_user :: auto-generated pointer for public function get_user
  def get_user(id, context, options \\ []), do: get(id, context, options)

  # <REMOVED UUID HERE> register :: auto-generated pointer for public function register
  def register(details, auth, context, options \\ [])

  def register(details, {:login, {email, password}}, context, options) do
    middle = details.name[:middle] && Enum.map(details.name.middle, &String.trim/1)

    name = %{
      first: details.name.first && String.trim(details.name.first),
      middle: middle,
      last: details.name.last && String.trim(details.name.last)
    }

    user_name = String.trim(details.user_name)

    handle =
      cond do
        details[:handle] ->
          details[:handle]

        :else ->
          {:ok, x} = generate_handle({name.first, name.last}, context, options)
          x
      end

    email = Starter.Users.Credentials.standardize_email(email)
    password = String.trim(password)
    status = Keyword.get(options, :status, details[:status] || :active)
    invite_token_id = Keyword.get(options, :invite_token_id, details[:invite_token_id])
    mobile_phone = Keyword.get(options, :mobile_phone, details[:mobile_phone])

    profile_completed_at =
      Keyword.get(options, :profile_completed_at, details[:profile_completed_at])

    with :valid <- valid_user_name?(details.user_name),
         :valid <- valid_name?(name.first, name.middle, name.last),
         :valid <- valid_login?(email, password),
         :valid <- user_name_available?(user_name, context, options),
         :valid <- login_available?(email, context, options) do
      Starter.Repo.transaction(fn ->
        with {:ok, name_record} <-
               %NameSchema{}
               |> NameSchema.changeset(%{
                 first: name.first,
                 middle: name.middle || [],
                 last: name.last
               })
               |> Starter.Repo.insert(),
             {:ok, description_record} <-
               %DescriptionSchema{}
               |> DescriptionSchema.changeset(%{
                 title: "Description",
                 body: details[:description] || "Registered user"
               })
               |> Starter.Repo.insert(),
             {:ok, user} <-
               %Schema{}
               |> Schema.changeset(%{
                 user_name: user_name,
                 handle: handle,
                 name_id: name_record.id,
                 description_id: description_record.id,
                 invite_token_id: invite_token_id,
                 email: email,
                 status: status,
                 mobile_phone: mobile_phone,
                 profile_completed_at: profile_completed_at,
                 approved_at: if(status == :active, do: DateTime.utc_now(), else: nil),
                 verified: false,
                 flagged: false
               })
               |> Starter.Repo.insert(),
             hashed_password = Bcrypt.hash_pwd_salt(password),
             auth_provider_id = UUID.uuid5(:oid, "Starter.Schema.Auth.Providers.Provider@Login"),
             {:ok, _auth_provider} <-
               Starter.Repo.insert(
                 %ProviderSchema{
                   id: auth_provider_id,
                   title: "Login",
                   description: "Email and password authentication"
                 },
                 on_conflict: :nothing,
                 conflict_target: :id
               ),
             {:ok, credential} <-
               %CredentialSchema{}
               |> CredentialSchema.changeset(%{
                 user_id: user.id,
                 auth_provider_id: auth_provider_id,
                 status: :active,
                 settings: %{"email" => email, "password" => hashed_password},
                 state: %{},
                 fingerprint: "#{email}:#{hashed_password}"
               })
               |> Starter.Repo.insert() do
          {user, credential}
        else
          {:error, reason} -> Starter.Repo.rollback(reason)
        end
      end)
    end
  end

  # <REMOVED UUID HERE> authenticate :: auto-generated pointer for public function authenticate
  def authenticate(auth = {:login, {_email, _password}}, context, options \\ nil) do
    with {:ok, session} <- Starter.Users.Credentials.authenticate(auth, context, options) do
      {:ok, session}
    end
  end

  # <REMOVED UUID HERE> by_handle :: auto-generated pointer for public function by_handle
  def by_handle(handle, context, options \\ []) do
    with record = %Schema{} <- Starter.Repo.get_by(Schema, %{handle: handle}) do
      settings = Noizu.Entity.Meta.persistence(Entity) |> hd
      {:ok, entity} = Entity.from_record(record, settings, context, options)
      __after_get__(entity, context, options)
    end
  end

  # <REMOVED UUID HERE> user_name_available? :: auto-generated pointer for public function user_name_available?
  def user_name_available?(user_name, _context, _options \\ nil) do
    with %{} <- Starter.Repo.get_by(Schema, %{user_name: user_name}) do
      {:error, {:user_name, :registered}}
    else
      nil -> :valid
      details -> {:error, {:user_name, {:internal_error, details}}}
    end
  end

  # <REMOVED UUID HERE> change_user :: auto-generated pointer for public function change_user
  def change_user(%Entity{} = user, attrs \\ %{}) do
    attrs =
      Enum.map(
        attrs,
        fn
          {"user_name", value} ->
            {:user_name, value}

          {"handle", value} ->
            {:handle, value}

          {"name", value} ->
            case user.name do
              %Ecto.Changeset{} ->
                value =
                  Starter.Versioned.Names.change(user.name.data, value)

                {:name, value}

              _ ->
                value =
                  Starter.Versioned.Names.change(
                    user.name || %Starter.Versioned.Names.Name{},
                    value
                  )

                {:name, value}
            end

          {"description", value} ->
            {:description, value}

          {"status", value} ->
            {:status, String.to_existing_atom(value)}

          {"verified", "true"} ->
            {:verified, true}

          {"verified", "false"} ->
            {:verified, false}

          {"verified", value} ->
            {:verified, value}

          {"flagged", "true"} ->
            {:flagged, true}

          {"flagged", "false"} ->
            {:flagged, false}

          {"flagged", value} ->
            {:flagged, value}

          {"id", value} ->
            {:id, value}

          {x, value} when is_atom(x) ->
            {x, value}

          _ ->
            nil
        end
      )
      |> Enum.reject(&is_nil/1)

    raw =
      Noizu.Entity.Meta.meta(Entity)[:changeset_fields]
      |> put_in(
        [:name],
        {:embed,
         %{
           __struct__: Ecto.Embedded,
           cardinality: :one,
           on_cast: :update,
           on_replace: :update,
           related: Starter.Versioned.Names.Name
         }}
      )

    Ecto.Changeset.change({user, raw}, attrs)
  end

  # ---------------------------------------------------------------------------
  # Validation Helpers
  # ---------------------------------------------------------------------------

  # <REMOVED UUID HERE> valid_user_name? :: auto-generated pointer for public function valid_user_name?
  def valid_user_name?(user_name) do
    cond do
      is_nil(user_name) -> {:error, {:user_name, :required}}
      String.length(user_name) == 0 -> {:error, {:user_name, :required}}
      String.length(user_name) > 32 -> {:error, {:user_name, :invalid}}
      String.match?(user_name, ~r/^[a-zA-Z0-9_\-]+$/) -> :valid
      :else -> {:error, {:user_name, :invalid}}
    end
  end

  # <REMOVED UUID HERE> valid_name? :: auto-generated pointer for public function valid_name?
  def valid_name?(first, middle, last) do
    cond do
      is_nil(first) ->
        {:error, {:name, {:first, :required}}}

      is_nil(last) ->
        {:error, {:name, {:last, :required}}}

      String.length(first) == 0 ->
        {:error, {:name, {:first, :required}}}

      String.length(last) == 0 ->
        {:error, {:name, {:last, :required}}}

      is_nil(middle) ->
        :valid

      is_list(middle) ->
        errors =
          Enum.reject(middle, fn
            x when is_bitstring(x) -> String.length(x) > 0
            _ -> false
          end)

        if errors == [] do
          :valid
        else
          {:error, {:name, {:middle, :invalid}}}
        end

      :else ->
        {:error, {:name, {:middle, :invalid}}}
    end
  end

  # <REMOVED UUID HERE> valid_login? :: auto-generated pointer for public function valid_login?
  def valid_login?(email, password) do
    Starter.Users.Credentials.valid_login?(email, password)
  end

  # <REMOVED UUID HERE> login_available? :: auto-generated pointer for public function login_available?
  def login_available?(email, context, options \\ nil) do
    Starter.Users.Credentials.login_available?(email, context, options)
  end

  # <REMOVED UUID HERE> generate_handle :: auto-generated pointer for public function generate_handle
  def generate_handle({first, last}, context, options \\ nil) do
    handle = String.slice(first, 0..1) <> String.slice(last, 0..32)
    unique_handle(handle, context, options)
  end

  defp unique_handle(handle, context, options) do
    case Starter.Users.by_handle(handle, context, options) do
      nil ->
        {:ok, handle}

      {:ok, _} ->
        Enum.reduce_while(0..999, handle, fn suffix, _acc ->
          with_suffix = handle <> String.pad_leading("#{suffix}", 3, "0")

          case Starter.Users.by_handle(with_suffix, context, options) do
            nil ->
              {:halt, {:ok, with_suffix}}

            {:ok, _} ->
              {:cont, handle}
          end
        end)
    end
  end
end
