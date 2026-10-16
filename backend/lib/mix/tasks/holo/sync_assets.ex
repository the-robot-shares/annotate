defmodule Mix.Tasks.Holo.SyncAssets do
  @moduledoc """
  Sync compiler-generated Hologram client assets into the Mix build priv copy.

  Why this exists: `:app` (which materializes priv/ into `_build/<env>/lib/<app>/priv`)
  runs BEFORE the `:hologram` compiler in the compile chain, so on a fresh build the
  client bundles the hologram compiler just wrote to `priv/static/hologram` may be
  missing from the priv the running app reads (`:code.priv_dir/1`). With the Hologram
  runtime enabled in :test (HOLOGRAM_START=1, see config/test.exs) the first page
  render then fails with `Hologram.AssetNotFoundError` on "hologram/runtime.js".

  Wired in front of the `test` alias (mix.exs), so it runs after compile and before
  the application boots; the resync is idempotent. On a fresh build Mix itself
  symlinks the build priv straight into the source tree
  (`Mix.Utils.symlink_or_copy`), in which case the target already IS the source and
  this task is a no-op — blind rm_rf+copy there would delete the source bundles
  through the symlink (File.CopyError ENOENT on the next line).
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    source = Path.join([File.cwd!(), "priv", "static", "hologram"])

    if File.dir?(source) do
      target =
        :annotate
        |> :code.priv_dir()
        |> to_string()
        |> Path.join("static/hologram")

      unless same_tree?(source, target) do
        File.rm_rf!(target)
        File.cp_r!(source, target)
      end
    end
  end

  # True when both paths resolve to the same directory (any symlink shape in
  # between: build priv -> source priv, or the hologram dir itself). stat
  # follows symlinks, so device+inode equality detects the shared tree.
  defp same_tree?(source, target) do
    case File.stat(target) do
      {:ok, target_stat} ->
        source_stat = File.stat!(source)

        {source_stat.major_device, source_stat.minor_device, source_stat.inode} ==
          {target_stat.major_device, target_stat.minor_device, target_stat.inode}

      {:error, _} ->
        false
    end
  end
end
