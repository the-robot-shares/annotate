defmodule Annotate.Redis do
  @channel_pool_size 50

  # <REMOVED UUID HERE> prefix :: auto-generated pointer for public function prefix
  def prefix(key) do
    case Application.get_env(:annotate, :redis)[:key_prefix] do
      nil -> key
      p -> "#{p}#{key}"
    end
  end

  # <REMOVED UUID HERE> get_channel :: auto-generated pointer for public function get_channel
  def get_channel() do
    (:persistent_term.get(:redis_channels, nil) || build_channels())[
      :rand.uniform(@channel_pool_size)
    ]
  end

  # <REMOVED UUID HERE> build_channels :: auto-generated pointer for public function build_channels
  def build_channels() do
    Enum.map(1..@channel_pool_size, &{&1, :"redis_#{&1}"})
    |> Map.new()
    |> tap(&:persistent_term.put(:redis_channels, &1))
  end

  # <REMOVED UUID HERE> child_spec :: auto-generated pointer for public function child_spec
  def child_spec(_args) do
    v = Application.get_env(:annotate, :redis)
    uri = v[:uri] || v[:host]
    settings = Redix.URI.to_start_options(uri)

    children =
      Enum.map(
        1..@channel_pool_size,
        fn index ->
          opts = put_in(settings, [:name], :"redis_#{index}")
          Supervisor.child_spec({Redix, opts}, id: {Redix, index})
        end
      )

    build_channels()

    %{
      id: RedixSupervisor,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(command), do: Redix.command(get_channel(), command)
  # <REMOVED UUID HERE> flush :: auto-generated pointer for public function flush
  def flush(), do: command(["FLUSHALL"])

  # <REMOVED UUID HERE> get :: auto-generated pointer for public function get
  def get(key) do
    command(["GET", prefix(key)])
  end

  # <REMOVED UUID HERE> del :: auto-generated pointer for public function del
  def del(key) do
    command(["DEL", prefix(key)])
  end

  # <REMOVED UUID HERE> set :: auto-generated pointer for public function set
  def set(key, value, options \\ []) do
    args =
      Enum.flat_map(options, fn
        {:ex, ttl} -> ["EX", to_string(ttl)]
        {:px, ttl} -> ["PX", to_string(ttl)]
        {:nx, true} -> ["NX"]
        {:xx, true} -> ["XX"]
      end)

    command(["SET", prefix(key), value | args])
  end

  # <REMOVED UUID HERE> get_binary :: auto-generated pointer for public function get_binary
  def get_binary(key) do
    case get(key) do
      {:ok, nil} ->
        nil

      {:ok, term} ->
        t = :erlang.binary_to_term(term)
        {:ok, t}

      _ ->
        nil
    end
  end

  # <REMOVED UUID HERE> set_binary :: auto-generated pointer for public function set_binary
  def set_binary(key, value, options \\ []) do
    encoded = :erlang.term_to_binary(value)
    set(key, encoded, options)
  end
end
