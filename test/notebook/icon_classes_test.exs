defmodule Notebook.IconClassesTest do
  use ExUnit.Case, async: true

  # Tailwind builds a hero-* class only when it reads its name in a file of
  # app.css's @source; an icon that no source names has an empty picture.
  test "app.css's sources name every one of the notebook's icons" do
    css = File.read!("assets/css/app.css")

    sources =
      for [_, path] <- Regex.scan(~r/^@source "([^"]+)";/m, css),
          do: Path.expand(path, "assets/css")

    files =
      Enum.flat_map(sources, fn source ->
        if File.dir?(source),
          do: Path.wildcard(Path.join(source, "**/*.{ex,heex,js,ts}")),
          else: [source]
      end)

    text = files |> Enum.filter(&File.regular?/1) |> Enum.map_join("\n", &File.read!/1)

    for {"hero-" <> _ = name, _label, _keywords} <- Notebook.Icon.icons() do
      assert text =~ name, "#{name} is in no @source of app.css: Tailwind does not build it"
    end
  end
end
