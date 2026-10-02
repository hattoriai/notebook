defmodule Notebook.Kotoba.Nodes.Callout do
  use Kotoba.Node, type: "notebook-callout", kind: :block, element: true
  alias Kotoba.Renderer

  @impl Kotoba.Node
  def render_html(node, opts),
    do: Renderer.tag("aside", [class: "notebook-callout"], Renderer.html_children(node, opts))

  @impl Kotoba.Node
  def render_text(node, opts), do: Renderer.text_children(node, opts)

  @impl Kotoba.Node
  def render_markdown(node, opts), do: "> **Note:** " <> Renderer.markdown_children(node, opts)
end
