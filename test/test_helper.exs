# SQLite takes one writer at a time, and each test is a transaction of
# the sandbox: tests at once would refuse each other's writes ("Database
# busy"), so they run one after the other.
ExUnit.start(max_cases: 1)
Ecto.Adapters.SQL.Sandbox.mode(Notebook.Repo, :manual)
