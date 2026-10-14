defmodule Starter.Support.NoizuJasonEncoder do
  @moduledoc false

  # <REMOVED UUID HERE> __using__ :: auto-generated pointer for public function __using__
  defmacro __using__(_opts \\ []) do
    quote do
      defimpl Jason.Encoder do
        # <REMOVED UUID HERE> encode :: auto-generated pointer for public function encode
        def encode(entity, {escape, encode_map, user_settings}) do
          json_format = user_settings[:json_format] || :default

          settings =
            Noizu.Entity.Meta.json(entity)[json_format] ||
              Noizu.Entity.Meta.json(entity)[:default]

          context = user_settings[:context]
          options = user_settings[:settings]

          entity
          |> Noizu.Entity.Json.Protocol.prep(settings, context, options)
          |> encode_prepared({escape, encode_map})
        end

        def encode(entity, opts) do
          settings = Noizu.Entity.Meta.json(entity)[:default]

          entity
          |> Noizu.Entity.Json.Protocol.prep(settings, Noizu.Context.system(), [])
          |> encode_prepared(opts)
        end

        defp encode_prepared(prepared, opts) when is_map(prepared),
          do: Jason.Encode.map(prepared, opts)

        defp encode_prepared(prepared, opts),
          do: Jason.Encode.value(prepared, opts)
      end
    end
  end
end
