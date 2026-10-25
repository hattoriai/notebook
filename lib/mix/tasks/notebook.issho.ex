defmodule Mix.Tasks.Notebook.Issho do
  @shortdoc "Builds Issho's browser client in deps/issho, from its main"

  @moduledoc """
  Builds the browser client of Issho, which the Notebook takes from its
  GitHub main until a release after 0.4.2: its repository holds the
  sources (`assets/src`, TypeScript), not the bundles a Hex package
  ships. Its ES module (`priv/static/issho.esm.js`, what `import "issho"`
  finds) is built with the Notebook's esbuild (the `:issho` profile), and
  its style sheets are copied beside it. `assets.build` and
  `assets.deploy` run it first.

      $ mix notebook.issho
  """
  use Mix.Task

  @deps Path.expand("../../../deps/issho", __DIR__)

  @impl Mix.Task
  def run(_args) do
    static = Path.join(@deps, "priv/static")
    File.mkdir_p!(static)
    Mix.Task.run("esbuild", ["issho"])

    for sheet <- ~w(issho.css issho-sumi.css),
        do: File.cp!(Path.join([@deps, "assets/css", sheet]), Path.join(static, sheet))
  end
end
