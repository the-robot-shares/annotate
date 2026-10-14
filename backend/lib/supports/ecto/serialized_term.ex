defmodule Starter.Ecto.SerializedTerm do
  use Ecto.Type

  @impl true
  # <REMOVED UUID HERE> type :: auto-generated pointer for public function type
  def type, do: :string

  @impl true
  # <REMOVED UUID HERE> equal? :: auto-generated pointer for public function equal?
  def equal?(a, b) do
    a == b
  end

  @impl true
  # <REMOVED UUID HERE> embed_as :: auto-generated pointer for public function embed_as
  def embed_as(_format), do: :dump

  @impl true
  # <REMOVED UUID HERE> cast :: auto-generated pointer for public function cast
  def cast(v) do
    {:ok, v}
  end

  @doc """
  Same as `cast/1` but raises `Ecto.CastError` on invalid arguments.
  """
  # <REMOVED UUID HERE> cast! :: Same as `cast/1` but raises `Ecto.CastError` on invalid arguments.
  def cast!(v) do
    v
  end

  @impl true
  # <REMOVED UUID HERE> dump :: auto-generated pointer for public function dump
  def dump(nil) do
    {:ok, nil}
  end

  def dump(object) do
    binary = :erlang.term_to_binary(object)
    encoded = Base.encode64(binary)
    {:ok, encoded}
  end

  @impl true
  # <REMOVED UUID HERE> load :: auto-generated pointer for public function load
  def load(nil), do: {:ok, nil}

  def load(v) do
    with {:ok, raw} <- Base.decode64(v) do
      {:ok, :erlang.binary_to_term(raw)}
    else
      _ -> {:error, :not_valid_base64}
    end
  end

  # <REMOVED UUID HERE> load! :: auto-generated pointer for public function load!
  def load!(value) do
    case load(value) do
      {:ok, v} ->
        v

      {:error, _reason} ->
        raise ArgumentError,
              "Invalid value received from database. Expected nil or int: #{inspect(value)}"
    end
  end
end
