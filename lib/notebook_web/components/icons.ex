defmodule NotebookWeb.Icons do
  @moduledoc """
  Notebook's own icons, each a function component on the same 24×24
  outline as Heroicons, so they sit beside `<.icon name="hero-…">`:

      <Icons.robot class="size-4" />

  The command palette's actions name them (`icon: "notebook-robot"` in
  `NotebookWeb.Commands`), and `named/1` renders them by that name.
  """
  use Phoenix.Component

  attr :rest, :global,
    default: %{
      "aria-hidden": "true",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": "1.6",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      viewBox: "0 0 24 24"
    }

  attr :class, :any, default: nil
  slot :inner_block, required: true

  defp svg_outline(assigns) do
    ~H"""
    <svg class={["notebook-icon", @class]} {@rest}>
      {render_slot(@inner_block)}
    </svg>
    """
  end

  @doc """
  The agents' robot: ink, with a blade orange bulb on its antenna, which
  blinks when its link is pointed at (app.css, `.notebook-robot-bulb`).
  """
  attr :class, :any, default: nil
  attr :rest, :global

  def robot(assigns) do
    ~H"""
    <.svg_outline class={@class} {@rest}>
      <path d="M12 6V4.4" />
      <circle class="notebook-robot-bulb" cx="12" cy="2.9" r="1.9" stroke="none" />
      <rect x="4.5" y="6" width="15" height="12" rx="4" />
      <path d="M2.5 10.5v3M21.5 10.5v3" />
      <circle cx="9.2" cy="11.3" r="1.4" fill="currentColor" stroke="none" />
      <circle cx="14.8" cy="11.3" r="1.4" fill="currentColor" stroke="none" />
      <path d="M9.6 14.6q2.4 1.5 4.8 0" />
      <path d="M9 18v2.2M15 18v2.2" />
    </.svg_outline>
    """
  end

  @doc "An icon of these, or a Heroicon, by its name: for the palette's actions."
  attr :name, :string, required: true
  attr :class, :any, default: nil

  def named(%{name: "notebook-robot"} = assigns), do: ~H"<.robot class={@class} />"
  def named(assigns), do: ~H"<NotebookWeb.CoreComponents.icon name={@name} class={@class} />"
end
