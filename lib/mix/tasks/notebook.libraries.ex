defmodule Mix.Tasks.Notebook.Libraries do
  @shortdoc "Builds the browser clients of the libraries the Notebook takes from GitHub"

  @moduledoc """
  Builds the browser clients of the libraries the Notebook takes from
  their GitHub main until their next releases (Issho, Kotoba, Hakushi,
  Masu): their repositories hold the sources (`assets/src`, TypeScript),
  not the bundles a Hex package ships. Each library's npm packages are
  installed (`npm ci`, again only when its lock changes), its ES modules
  (`priv/static/*.esm.js`, what `import "kotoba"` finds) are built with
  the Notebook's esbuild, with the same arguments as its own build, and
  its style sheets are copied beside them. `assets.build` and
  `assets.deploy` run it first.

      $ mix notebook.libraries
  """
  use Mix.Task

  @deps Path.expand("../../../deps", __DIR__)

  # Each library: its esbuild profiles (config/config.exs) and its sheets.
  @libraries [
    issho: {[:issho], ~w(issho.css issho-sumi.css)},
    kotoba: {[:kotoba, :kotoba_collab], ~w(kotoba.css kotoba-sumi.css)},
    hakushi: {[:hakushi], ~w(hakushi.css hakushi-sumi.css)},
    masu: {[:masu], ~w(masu.css masu-sumi.css)}
  ]

  @impl Mix.Task
  def run(_args) do
    for {library, {profiles, sheets}} <- @libraries do
      dir = Path.join(@deps, to_string(library))
      static = Path.join(dir, "priv/static")
      File.mkdir_p!(static)
      install(Path.join(dir, "assets"))
      Enum.each(profiles, &Mix.Task.rerun("esbuild", [to_string(&1)]))

      for sheet <- sheets,
          do: File.cp!(Path.join([dir, "assets/css", sheet]), Path.join(static, sheet))
    end
  end

  # Its npm packages, when it has any, and only when its lock changed.
  defp install(assets) do
    lock = Path.join(assets, "package-lock.json")
    stamp = Path.join(assets, "node_modules/.notebook-lock-sha256")

    with true <- File.exists?(lock) and dependencies?(assets),
         hash = :crypto.hash(:sha256, File.read!(lock)) |> Base.encode16(case: :lower),
         false <- File.read(stamp) == {:ok, hash} do
      npm = System.find_executable("npm") || Mix.raise("mix notebook.libraries needs npm")

      case System.cmd(npm, ["ci", "--omit=dev", "--prefix", assets], stderr_to_stdout: true) do
        {_output, 0} -> File.write!(stamp, hash)
        {output, status} -> Mix.raise("npm ci in #{assets} exited with #{status}:\n#{output}")
      end
    end

    :ok
  end

  defp dependencies?(assets) do
    assets
    |> Path.join("package.json")
    |> File.read!()
    |> JSON.decode!()
    |> Map.has_key?("dependencies")
  end
end
