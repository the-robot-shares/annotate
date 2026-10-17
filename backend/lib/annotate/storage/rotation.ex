defmodule Annotate.Storage.Rotation do
  @moduledoc """
  Rolling storage cap for comment attachments.

  After any successful attachment upload the stored total must be back under
  the cap (`ANNOTATE_COMMENT_STORAGE_CAP_GB`, default 1 GB). When it is not,
  the OLDEST attachments are evicted FIFO — ordered by `inserted_at` — each
  eviction deleting the storage object AND the attachment row, one
  transaction per deletion, logged with id + bytes.

  Scope (safety): the `attachments` table ONLY — comment-attachment uploads,
  both `pending` and `ready`. The dashboard `media`/asset tables are a
  different feature and are never touched, and neither is anything else that
  shares the bucket. Deleting old user content here is explicitly authorized
  by the site owner (2026-10-18); no manual one-off deletion runs against
  prod in this task.
  """

  require Logger

  import Ecto.Query

  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Attachment
  alias Annotate.Storage

  @doc "Cap in bytes from `ANNOTATE_COMMENT_STORAGE_CAP_GB` (default 1)."
  def cap_bytes do
    env = Application.get_env(:annotate, :comment_storage, [])
    gb = if is_integer(env[:cap_gb]) and env[:cap_gb] > 0, do: env[:cap_gb], else: 1
    gb * 1024 * 1024 * 1024
  end

  def configured?, do: is_binary(Storage.config()[:bucket]) and Storage.config()[:bucket] != ""

  @doc """
  Enforces the cap; evicts oldest-first while over. Returns
  `{:ok, evicted_count}` | `{:error, reason}` (error stops the pass — the
  next upload re-runs it).
  """
  def enforce do
    if configured?(), do: enforce(cap_bytes()), else: {:ok, 0}
  end

  def enforce(cap) when is_integer(cap) and cap > 0 do
    if total_bytes() > cap do
      case oldest_attachment() do
        nil ->
          {:ok, 0}

        victim ->
          case evict_one(victim) do
            :ok ->
              case enforce(cap) do
                {:ok, n} -> {:ok, n + 1}
                error -> error
              end

            error ->
              error
          end
      end
    else
      {:ok, 0}
    end
  end

  def enforce(_), do: {:ok, 0}

  # Ecto's `sum/1` loads as a %Decimal{} (and a struct compares greater than
  # ANY number in Erlang term order — the cap check would then always be
  # "over" and the rotation would evict everything). Convert before comparing.
  defp total_bytes do
    Repo.one!(
      from(a in Attachment, where: not is_nil(a.storage_key), select: coalesce(sum(a.bytes), 0))
    )
    |> total_to_integer()
  end

  defp total_to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp total_to_integer(n) when is_integer(n), do: n
  defp total_to_integer(nil), do: 0

  defp oldest_attachment do
    Repo.one(
      from(a in Attachment,
        where: not is_nil(a.storage_key),
        order_by: [asc: a.inserted_at, asc: a.id],
        limit: 1
      )
    )
  end

  # Object first (a failed object delete halts the pass; a failed row delete
  # after object deletion would strand the row against a missing object, so
  # the transaction wraps only the row).
  defp evict_one(%Attachment{} = victim) do
    case Storage.delete_object(victim.storage_key) do
      {:ok, _} ->
        Repo.transaction(fn -> Repo.delete!(victim) end)

        Logger.info(
          "[storage-rotation] evicted attachment id=#{victim.id} bytes=#{victim.bytes || 0} " <>
            "inserted_at=#{victim.inserted_at}"
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "[storage-rotation] object delete failed id=#{victim.id}: #{inspect(reason)} — halting this pass"
        )

        {:error, :object_delete_failed}
    end
  end
end
