defmodule Notebook.Repo.Migrations.CreateSpaces do
  use Ecto.Migration

  # Pages go in spaces: General, which every account is in; each person's
  # Private space; and the team spaces people make. A space has folders,
  # two levels deep at most, and a page is in a space and maybe a folder.
  # The pages of the one shared notebook move to General, and each account
  # gets its Private space.
  def up do
    create table(:spaces) do
      add :name, :string, null: false
      add :kind, :string, null: false
      add :description, :string
      add :owner_id, references(:users, on_delete: :delete_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:spaces, [:kind], where: "kind = 'general'", name: :spaces_one_general)

    create unique_index(:spaces, [:owner_id],
             where: "kind = 'private'",
             name: :spaces_one_private
           )

    create table(:space_members) do
      add :space_id, references(:spaces, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:space_members, [:space_id, :user_id])
    create index(:space_members, [:user_id])

    create table(:folders) do
      add :name, :string, null: false
      add :space_id, references(:spaces, on_delete: :delete_all), null: false
      add :parent_id, references(:folders, on_delete: :delete_all)
      timestamps(type: :utc_datetime)
    end

    create index(:folders, [:space_id])
    create index(:folders, [:parent_id])

    alter table(:pages) do
      add :space_id, references(:spaces, on_delete: :delete_all)
      add :folder_id, references(:folders, on_delete: :nilify_all)
      add :archived_at, :utc_datetime
    end

    create index(:pages, [:space_id])
    create index(:pages, [:folder_id])

    flush()

    now = "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"

    execute """
    INSERT INTO spaces (name, kind, description, inserted_at, updated_at)
    VALUES ('General', 'general', 'Everyone in the notebook.', #{now}, #{now})
    """

    execute """
    INSERT INTO space_members (space_id, user_id, role, inserted_at, updated_at)
    SELECT (SELECT id FROM spaces WHERE kind = 'general'), id, 'editor', #{now}, #{now} FROM users
    """

    execute """
    INSERT INTO spaces (name, kind, owner_id, inserted_at, updated_at)
    SELECT 'Private', 'private', id, #{now}, #{now} FROM users
    """

    execute """
    INSERT INTO space_members (space_id, user_id, role, inserted_at, updated_at)
    SELECT id, owner_id, 'admin', #{now}, #{now} FROM spaces WHERE kind = 'private'
    """

    execute "UPDATE pages SET space_id = (SELECT id FROM spaces WHERE kind = 'general')"
  end

  def down do
    drop index(:pages, [:folder_id])
    drop index(:pages, [:space_id])

    alter table(:pages) do
      remove :archived_at
      remove :folder_id
      remove :space_id
    end

    drop table(:folders)
    drop table(:space_members)
    drop table(:spaces)
  end
end
