defimpl Phoenix.Param, for: Notebook.Pages.Page do
  # A page's address in the notebook: its slug (/pages/kotoba), else its id.
  def to_param(%{slug: slug}) when is_binary(slug) and slug != "", do: slug
  def to_param(%{id: id}), do: Integer.to_string(id)
end
