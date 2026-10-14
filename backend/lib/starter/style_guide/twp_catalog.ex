defmodule Starter.StyleGuide.TwpCatalog do
  @moduledoc """
  Compile-time loader for the Tailwind Plus demo registry.

  Reads `priv/static/twp/registry.json` once at compile time and exposes
  pure lookup helpers. JSON maps keep string keys (Jason default) to avoid
  atom exhaustion.
  """

  # __DIR__ is lib/styleguide → project root is ../..
  @registry_path Path.expand("../../../priv/static/twp/registry.json", __DIR__)
  @external_resource @registry_path
  @registry Jason.decode!(File.read!(@registry_path))

  @doc """
  All sections from the registry (string-keyed maps with id, label, groups).
  """
  @spec sections() :: [map()]
  # <REMOVED UUID HERE> sections :: All sections from the registry (string-keyed maps with id, label, groups).
  def sections do
    Map.get(@registry, "sections", [])
  end

  @doc """
  Lookup a single section by id. Returns nil when not found.
  """
  @spec section(String.t()) :: map() | nil
  # <REMOVED UUID HERE> section :: Lookup a single section by id.
  def section(id) when is_binary(id) do
    Enum.find(sections(), &(&1["id"] == id))
  end

  @doc """
  Groups for a section id. Returns [] when the section is missing.
  """
  @spec groups(String.t()) :: [map()]
  # <REMOVED UUID HERE> groups :: Groups for a section id.
  def groups(section_id) when is_binary(section_id) do
    case section(section_id) do
      nil -> []
      sec -> Map.get(sec, "groups", [])
    end
  end

  @doc """
  Find one demo entry by section id, group label, and export name.
  """
  @spec find_entry(String.t(), String.t(), String.t()) :: map() | nil
  # <REMOVED UUID HERE> find_entry :: Find one demo entry by section id, group label, and export name.
  def find_entry(section_id, group_label, export_name)
      when is_binary(section_id) and is_binary(group_label) and is_binary(export_name) do
    groups(section_id)
    |> Enum.find(&(&1["label"] == group_label))
    |> case do
      nil ->
        nil

      group ->
        Enum.find(Map.get(group, "entries", []), &(&1["exportName"] == export_name))
    end
  end

  @doc """
  Default selection: first section / first group / first entry.

  Returns `{section_id, group_label, entry}` or `nil` if the registry is empty.
  """
  @spec first_entry() :: {String.t(), String.t(), map()} | nil
  # <REMOVED UUID HERE> first_entry :: Default selection: first section / first group / first entry.
  def first_entry do
    with [sec | _] <- sections(),
         section_id when is_binary(section_id) <- sec["id"],
         [group | _] <- Map.get(sec, "groups", []),
         group_label when is_binary(group_label) <- group["label"],
         [entry | _] <- Map.get(group, "entries", []) do
      {section_id, group_label, entry}
    else
      _ -> nil
    end
  end

  @doc """
  Registry stats map (`ok`, `stub`, `total`, etc.).
  """
  @spec stats() :: map()
  # <REMOVED UUID HERE> stats :: Registry stats map (`ok`, `stub`, `total`, etc.).
  def stats do
    Map.get(@registry, "stats", %{"ok" => 0, "stub" => 0, "total" => 0})
  end

  @doc """
  Case-insensitive search over entry `name` and `exportName`.

  Returns a flat list of matching entry maps (string keys).
  Empty query returns [].
  """
  @spec search(String.t()) :: [map()]
  # <REMOVED UUID HERE> search :: Case-insensitive search over entry `name` and `exportName`.
  def search(query) when is_binary(query) do
    q = String.downcase(String.trim(query))

    if q == "" do
      []
    else
      for section <- sections(),
          group <- Map.get(section, "groups", []),
          entry <- Map.get(group, "entries", []),
          match_entry?(entry, q),
          do: entry
    end
  end

  defp match_entry?(entry, q) do
    name = entry |> Map.get("name", "") |> String.downcase()
    export = entry |> Map.get("exportName", "") |> String.downcase()
    String.contains?(name, q) or String.contains?(export, q)
  end
end
