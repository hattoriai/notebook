defmodule Notebook.Storage.Config do
  @moduledoc """
  Where the files are: `kind` is `"local"` (this server's disk) or
  `"bucket"`; a bucket's provider, endpoint, region, name and key, and
  how its files are served (`"app"`, through the notebook; `"redirect"`,
  to a link the bucket signs for a few minutes).
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :kind, :string, default: "local"
    field :provider, :string, default: "aws"
    field :endpoint, :string
    field :region, :string
    field :bucket, :string
    field :access_key_id, :string
    field :secret_access_key, :string, redact: true
    field :serve, :string, default: "app"
    # Whether a secret is kept: the form never shows it.
    field :secret?, :boolean, virtual: true, default: false
  end
end
