defmodule NotebookWeb.IconEdit do
  @moduledoc """
  The icon of a space or a page, as its editors change it (`Notebook.Icon`),
  as Notion's: Erabi's emoji picker with the tabs Emoji, Icons (the
  notebook's) and Upload (an image of its own), and Remove at the top.

  The LiveView handles `event` (`%{"icon" => icon}`, `""` to remove it),
  and stores the upload `upload` when it is done.
  """
  use NotebookWeb, :html

  attr :id, :string, required: true, doc: "the DOM id of the whole; the picker's comes from it"
  attr :icon, :string, default: nil
  attr :label, :string, required: true, doc: "the picker's label, as \"Kotoba's icon\""
  attr :event, :string, required: true
  attr :upload, :any, required: true, doc: "the LiveView upload of an image"
  attr :class, :any, default: nil

  def icon_edit(assigns) do
    ~H"""
    <div class={["icon-edit", @class]} id={@id}>
      <form id={"#{@id}-form"} phx-change={@event}>
        <Erabi.Components.emoji_picker
          id={picker_id(@id, @icon)}
          name="icon"
          value={@icon}
          options={options(@icon)}
          label={@label}
          placeholder="Choose an icon"
          clearable={false}
        >
          <:icon :let={name}><Icons.named name={name} class="size-5" /></:icon>
          <%!-- As Notion's: Emoji, Icons, and Upload; Remove at the top. Plain
          HTML: a component in the picker comes back empty (data-phx-skip)
          when the picker mounts again with a new id. --%>
          <:tab label="Upload">
            <div class="icon-edit-upload-tab">
              <label for={@upload.ref} class="button" id={"#{@id}-upload-label"}>
                <span class="hero-photo size-4" aria-hidden="true"></span> Upload an image
              </label>
              <p>A PNG, JPEG, GIF or WebP, up to 2 MB. Square images look best.</p>
            </div>
          </:tab>
          <:action :if={@icon}>
            <button type="button" id={"#{@id}-reset"} phx-click={@event} phx-value-icon="">Remove</button>
          </:action>
        </Erabi.Components.emoji_picker>
      </form>
      <%!-- The file input the Upload tab's label opens: LiveView's, outside the picker. --%>
      <form id={"#{@id}-upload"} phx-change="icon_upload" class="sr-only">
        <.live_file_input upload={@upload} />
      </form>
      <p :for={error <- errors(@upload)} class="field-error" role="alert">{error}</p>
    </div>
    """
  end

  # Erabi's picker ignores LiveView's patches inside it (phx-update="ignore"),
  # so it never sees the <template> of a new image: a new image is a new
  # picker, which mounts again with it.
  # The same holds for its Remove, there only with an icon.
  defp picker_id(id, "image:" <> url), do: "#{id}-picker-#{:erlang.phash2(url)}"
  defp picker_id(id, nil), do: "#{id}-picker-none"
  defp picker_id(id, _icon), do: "#{id}-picker"

  # The notebook's icons, as the emoji picker's second tab; first, the own
  # image, when there is one, so the picker shows it and it can be chosen
  # again.
  defp options(icon) do
    own =
      case icon do
        "image:" <> _ -> [%{value: icon, label: "Its image", icon: icon, keywords: ~w(upload)}]
        _other -> []
      end

    own ++
      for {name, label, keywords} <- Notebook.Icon.icons(),
          do: %{value: name, label: label, icon: name, keywords: keywords}
  end

  defp errors(upload) do
    errors = upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1))
    errors |> Enum.uniq() |> Enum.map(&error/1)
  end

  defp error(:too_large), do: "The image is larger than 2 MB."
  defp error(:not_accepted), do: "Use a PNG, JPEG, GIF or WebP image."
  defp error(_error), do: "The image could not be uploaded."

  @doc "The upload of an icon's image, for `allow_upload/3`, with its `progress` callback."
  def upload_options(progress),
    do: [
      accept: ~w(.png .jpg .jpeg .gif .webp),
      max_entries: 1,
      max_file_size: 2_000_000,
      auto_upload: true,
      progress: progress
    ]
end
