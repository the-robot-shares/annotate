defmodule Starter.EntityUIDConcurrencyTest do
  # Regression: noizu_labs_entities <= 0.3.1 minted entity ids from
  # `{ms_timestamp, 0}` (Noizu.Entity.UID.Stub), so two inserts into the same
  # table within one millisecond collided on `versioned_*_pkey`. 0.3.2's default
  # provider must keep concurrent creates unique. Fails against the stub.
  # 0.3.2 also minted ids with an uppercase uuid tail that Postgres returned
  # lowercased, so a created id no longer matched its fetched id; 0.3.4 fixes
  # that — every created entity must round-trip by id.
  use Starter.DataCase, async: false

  @count 50

  test "concurrent entity creates all succeed with unique ids" do
    context = Noizu.Context.system()

    results =
      1..@count
      |> Task.async_stream(
        fn i ->
          try do
            %Starter.Versioned.Names.Name{
              first: "UID race #{i}",
              middle: [],
              last: "#{System.unique_integer([:positive])}",
              time_stamp: Noizu.Entity.TimeStamp.now()
            }
            |> Starter.EntityRepo.create(context)
          rescue
            e -> {:error, e}
          end
        end,
        max_concurrency: @count,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    failures = Enum.reject(results, &match?({:ok, _}, &1))

    assert failures == [],
           "#{length(failures)}/#{@count} creates failed: #{inspect(hd(failures ++ [nil]))}"

    ids = Enum.map(results, fn {:ok, entity} -> entity.id end)
    assert length(Enum.uniq(ids)) == @count

    for {:ok, created} <- results do
      assert {:ok, fetched} =
               Starter.EntityRepo.get({:ref, Starter.Versioned.Names.Name, created.id}, context)

      assert fetched.id == created.id
    end

    import Ecto.Query

    listed =
      Starter.Repo.all(
        from n in Starter.Schema.Versioned.Names.Name, where: n.id in ^ids, select: n.id
      )

    assert MapSet.new(listed) == MapSet.new(ids)
  end
end
