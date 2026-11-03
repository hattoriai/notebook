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
      "stroke-width": "1.5",
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
      <path d="M12 7.25V5.4" />
      <circle class="notebook-robot-bulb" cx="12" cy="3.4" r="2.1" stroke="none" />
      <rect x="3.75" y="7.25" width="16.5" height="13.25" rx="4.25" />
      <path d="M1.75 12.25v3.25M22.25 12.25v3.25" />
      <circle cx="8.9" cy="12.9" r="1.6" fill="currentColor" stroke="none" />
      <circle cx="15.1" cy="12.9" r="1.6" fill="currentColor" stroke="none" />
      <path d="M9.25 16.4q2.75 1.7 5.5 0" />
    </.svg_outline>
    """
  end

  @doc "An icon of these, or a Heroicon, by its name: for the palette's actions."
  attr :name, :string, required: true
  attr :class, :any, default: nil

  def named(%{name: "notebook-robot"} = assigns), do: ~H"<.robot class={@class} />"
  def named(assigns), do: ~H"<NotebookWeb.CoreComponents.icon name={@name} class={@class} />"
end
