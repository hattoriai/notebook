defmodule Notebook.Repo.Migrations.AddSearch do
  use Ecto.Migration

  # Full-text search of the pages (SQLite's FTS5): each page's title, its
  # text, and its records (a table page's rows, a database page's records),
  # by its id. Words are matched without case or accents ("hojicha" finds
  # "Hōjicha"). Triggers keep it as the pages, the rows and the records
  # change; what is there now is put in at once.
  def up do
    execute """
    CREATE VIRTUAL TABLE pages_fts USING fts5(
      title, body, records,
      tokenize = 'unicode61 remove_diacritics 2',
      prefix = '2 3'
    )
    """

    # A page's text, and its records' words.
    body = "coalesce(json_extract(p.body, '$.text'), '')"

    rows = fn page ->
      "(SELECT coalesce(group_concat(coalesce(r.title, '') || ' ' || coalesce(r.owner, '') || ' ' || coalesce(r.status, ''), ' '), '') FROM page_rows r WHERE r.page_id = #{page})"
    end

    records = fn page ->
      """
      (SELECT coalesce(group_concat(coalesce(cr.search_text, ''), ' '), '')
       FROM cardbox_records cr JOIN cardbox_collections cc ON cc.id = cr.collection_id
       WHERE cc.owner_type = 'page' AND cc.owner_id = CAST(#{page} AS TEXT))
      """
    end

    words = fn page -> "#{rows.(page)} || ' ' || #{records.(page)}" end

    execute """
    INSERT INTO pages_fts (rowid, title, body, records)
    SELECT p.id, coalesce(p.title, ''), #{body}, #{words.("p.id")} FROM pages p
    """

    execute """
    CREATE TRIGGER pages_fts_insert AFTER INSERT ON pages BEGIN
      INSERT INTO pages_fts (rowid, title, body, records)
      SELECT p.id, coalesce(p.title, ''), #{body}, '' FROM pages p WHERE p.id = NEW.id;
    END
    """

    execute """
    CREATE TRIGGER pages_fts_update AFTER UPDATE OF title, body ON pages BEGIN
      UPDATE pages_fts SET title = coalesce(NEW.title, ''),
        body = (SELECT #{body} FROM pages p WHERE p.id = NEW.id)
      WHERE rowid = NEW.id;
    END
    """

    execute """
    CREATE TRIGGER pages_fts_delete AFTER DELETE ON pages BEGIN
      DELETE FROM pages_fts WHERE rowid = OLD.id;
    END
    """

    for {table, page} <- [{"page_rows", "page_id"}],
        {event, row} <- [{"INSERT", "NEW"}, {"UPDATE", "NEW"}, {"DELETE", "OLD"}] do
      execute """
      CREATE TRIGGER #{table}_fts_#{String.downcase(event)} AFTER #{event} ON #{table} BEGIN
        UPDATE pages_fts SET records = #{words.("#{row}.#{page}")} WHERE rowid = #{row}.#{page};
      END
      """
    end

    page_of = fn row ->
      "(SELECT CAST(cc.owner_id AS INTEGER) FROM cardbox_collections cc WHERE cc.id = #{row}.collection_id AND cc.owner_type = 'page')"
    end

    for {event, row} <- [{"INSERT", "NEW"}, {"UPDATE", "NEW"}, {"DELETE", "OLD"}] do
      execute """
      CREATE TRIGGER cardbox_records_fts_#{String.downcase(event)} AFTER #{event} ON cardbox_records BEGIN
        UPDATE pages_fts SET records = #{words.(page_of.(row))} WHERE rowid = #{page_of.(row)};
      END
      """
    end
  end

  def down do
    for event <- ~w(insert update delete) do
      execute "DROP TRIGGER IF EXISTS cardbox_records_fts_#{event}"
      execute "DROP TRIGGER IF EXISTS page_rows_fts_#{event}"
    end

    execute "DROP TRIGGER IF EXISTS pages_fts_delete"
    execute "DROP TRIGGER IF EXISTS pages_fts_update"
    execute "DROP TRIGGER IF EXISTS pages_fts_insert"
    execute "DROP TABLE IF EXISTS pages_fts"
  end
end
