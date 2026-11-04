defmodule Notebook.Icon do
  @moduledoc """
  The icon of a space or a page: one of the notebook's icons (`icons/0`),
  an emoji Erabi's picker has, or an image of its own (`"image:<url>"`),
  stored with Storehouse. The image an icon had goes when it has another.
  """

  import Ecto.Changeset

  @doc """
  The notebook's icons, besides an emoji or an image: `{name, label,
  keywords}`, as `NotebookWeb.Icons.named/1` draws them.
  """
  def icons do
    [
      {"hero-user-group", "Team", ~w(people group)},
      {"hero-building-office-2", "Office", ~w(company organisation)},
      {"hero-lock-closed", "Private", ~w(lock secret)},
      {"hero-briefcase", "Work", ~w(job business)},
      {"hero-rocket-launch", "Launch", ~w(project start)},
      {"hero-light-bulb", "Ideas", ~w(idea brainstorm)},
      {"hero-beaker", "Research", ~w(lab science)},
      {"hero-code-bracket", "Engineering", ~w(code dev)},
      {"hero-paint-brush", "Design", ~w(art brand)},
      {"hero-megaphone", "Marketing", ~w(announce)},
      {"hero-chart-bar", "Numbers", ~w(chart data finance)},
      {"hero-currency-dollar", "Money", ~w(finance sales)},
      {"hero-academic-cap", "Learning", ~w(school course)},
      {"hero-book-open", "Reading", ~w(book library)},
      {"hero-heart", "Care", ~w(love health)},
      {"hero-sparkles", "Magic", ~w(shiny new)},
      {"hero-fire", "Hot", ~w(fire urgent)},
      {"hero-globe-alt", "World", ~w(web global)},
      {"hero-home", "Home", ~w(house)},
      {"hero-camera", "Photos", ~w(photo media)},
      {"hero-musical-note", "Music", ~w(song audio)},
      {"hero-puzzle-piece", "Puzzle", ~w(game)},
      {"hero-wrench-screwdriver", "Tools", ~w(ops fix)},
      {"hero-calendar-days", "Plans", ~w(calendar schedule)},
      {"notebook-robot", "Agents", ~w(robot bot ai)}
    ]
  end

  @doc "The icon of a changeset's `:icon`, checked; an empty one is none."
  def change_icon(struct_or_changeset, icon) do
    struct_or_changeset
    |> change(icon: blank(icon))
    |> validate_change(:icon, fn :icon, icon ->
      if valid?(icon), do: [], else: [icon: "is not an icon"]
    end)
  end

  @doc "Whether `icon` is an icon: one of `icons/0`, an emoji, or an image of the notebook's."
  def valid?("image:" <> url), do: String.starts_with?(url, ["/", "https://"])
  def valid?(icon) when is_binary(icon), do: icon in names() or emoji?(icon)
  def valid?(_icon), do: false

  defp names, do: for({name, _label, _keywords} <- icons(), do: name)

  # An emoji Erabi's picker has (in any skin tone).
  defp emoji?(icon), do: Erabi.Emoji.name(icon, "en") != nil

  defp blank(""), do: nil
  defp blank(icon), do: icon

  @doc """
  Stores an uploaded image for an icon, from `path`: a PNG, JPEG, GIF or
  WebP by its bytes (not an SVG, which can hold a script), at most 2 MB.
  """
  def store_image(path, name) do
    case Storehouse.store(path,
           name: name,
           accept: ~w(image/png image/jpeg image/gif image/webp),
           max_bytes: 2_000_000
         ) do
      {:ok, file} -> {:ok, file}
      {:existing, file} -> {:ok, file}
      {:error, reason} -> {:error, {:image, reason}}
    end
  end

  @doc "Deletes a stored image that was just stored, when its icon was not saved."
  def delete_stored(%{key: key}), do: Notebook.Storage.adapter().delete(key)

  @doc "Deletes the image an icon had, once it has another icon (or none)."
  def discard_image("image:" <> url = old, new) when old != new do
    with "/uploads/kotoba/" <> key <- url, do: Notebook.Storage.store_of(key).delete(key)
    :ok
  end

  def discard_image(_old, _new), do: :ok

  @doc "The storage key of an icon's image, or nil."
  def image_key("image:/uploads/kotoba/" <> key), do: key
  def image_key(_icon), do: nil
end
