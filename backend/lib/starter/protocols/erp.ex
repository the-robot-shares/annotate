require Protocol
Protocol.derive(Jason.Encoder, Noizu.Entity.TimeStamp, [])

defimpl Jason.Encoder, for: Tuple do
  # <REMOVED UUID HERE> encode :: auto-generated pointer for public function encode
  def encode({:ref, _, _} = s, opts) do
    with {:ok, sref} <- Noizu.EntityReference.Protocol.sref(s) do
      sref
      |> encode_string(opts)
    else
      {:error, _} -> {:error, :invalid_sref}
    end
  end

  def encode(s, opts) do
    "#{inspect(s)}"
    |> encode_string(opts)
  end

  defp encode_string(value, {escape, encode_map, _user_settings}) do
    Jason.Encode.string(value, {escape, encode_map})
  end

  defp encode_string(value, opts) do
    Jason.Encode.string(value, opts)
  end
end

defimpl Noizu.EntityReference.Protocol, for: BitString do
  # <REMOVED UUID HERE> handlers :: auto-generated pointer for public function handlers
  def handlers() do
    Starter.EntityRepo.sref_handlers()
  end

  # <REMOVED UUID HERE> handler :: auto-generated pointer for public function handler
  def handler("ref." <> _ = sref) do
    with [_, h] <- Regex.run(~r/^ref.([^.]*)/, sref) do
      h = handlers()[h]
      (h && {:ok, h}) || {:error, {:handler_not_found, sref}}
    else
      _ -> {:error, {:handler_not_found, sref}}
    end
  end

  def handler(sref), do: {:error, {:handler_not_found, sref}}

  # <REMOVED UUID HERE> id :: auto-generated pointer for public function id
  def id(subject) do
    with {:ok, handler} <- handler(subject) do
      apply(handler, :id, [subject])
    end
  end

  # <REMOVED UUID HERE> kind :: auto-generated pointer for public function kind
  def kind(subject) do
    with {:ok, handler} <- handler(subject) do
      apply(handler, :kind, [subject])
    end
  end

  # <REMOVED UUID HERE> ref :: auto-generated pointer for public function ref
  def ref(subject) do
    with {:ok, handler} <- handler(subject) do
      apply(handler, :ref, [subject])
    end
  end

  # <REMOVED UUID HERE> sref :: auto-generated pointer for public function sref
  def sref(subject) do
    with {:ok, handler} <- handler(subject) do
      apply(handler, :sref, [subject])
    end
  end

  # <REMOVED UUID HERE> entity :: auto-generated pointer for public function entity
  def entity(subject, context) do
    with {:ok, handler} <- handler(subject) do
      apply(handler, :entity, [subject, context])
    end
  end
end
