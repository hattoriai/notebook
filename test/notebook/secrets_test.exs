defmodule Notebook.SecretsTest do
  # The vault is the node's: these run alone.
  use Notebook.DataCase, async: false

  alias Notebook.{Repo, Secrets, Vault}

  @old Base.encode64(:binary.copy(<<1>>, 32))
  @new Base.encode64(:binary.copy(<<2>>, 32))

  # The vault again, with the keys of the environment now.
  defp restart_vault(env) do
    for {name, value} <- env,
        do: if(value, do: System.put_env(name, value), else: System.delete_env(name))

    :ok = Supervisor.terminate_child(Notebook.Supervisor, Vault)
    {:ok, _pid} = Supervisor.restart_child(Notebook.Supervisor, Vault)
  end

  setup do
    on_exit(fn ->
      restart_vault(%{"NOTEBOOK_VAULT_KEY" => nil, "NOTEBOOK_VAULT_RETIRED_KEYS" => nil})
    end)
  end

  defp raw(name) do
    %{rows: [[value]]} = Repo.query!("SELECT value FROM secrets WHERE name = ?", [name])
    value
  end

  test "a secret is kept encrypted, and given back" do
    :ok = Secrets.put("storage.secret_access_key", "no-more-swords")
    assert Secrets.get("storage.secret_access_key") == "no-more-swords"
    refute raw("storage.secret_access_key") =~ "no-more-swords"
    # Its key's tag, at its start: a secret names the key it needs.
    assert String.contains?(raw("storage.secret_access_key"), Vault.tag())

    :ok = Secrets.put("storage.secret_access_key", "a new one")
    assert Secrets.get("storage.secret_access_key") == "a new one"
    :ok = Secrets.delete("storage.secret_access_key")
    assert Secrets.get("storage.secret_access_key") == nil
  end

  test "keys rotate: the old ones still open, until the secrets are encrypted again" do
    # Without a key of its own: one from SECRET_KEY_BASE.
    :ok = Secrets.put("webhook", "the first")

    # A key set the first time: the derived one is retired at once.
    restart_vault(%{"NOTEBOOK_VAULT_KEY" => @old})
    assert Secrets.get("webhook") == "the first"
    assert Secrets.rotate() == 1
    assert String.contains?(raw("webhook"), Vault.tag(Base.decode64!(@old)))

    # Another key, the old one retired.
    restart_vault(%{"NOTEBOOK_VAULT_KEY" => @new, "NOTEBOOK_VAULT_RETIRED_KEYS" => @old})
    assert Secrets.get("webhook") == "the first"
    assert Secrets.rotate() == 1
    assert String.contains?(raw("webhook"), Vault.tag(Base.decode64!(@new)))

    # The old key gone: what it encrypted is to be given again, nothing breaks.
    restart_vault(%{"NOTEBOOK_VAULT_KEY" => @old, "NOTEBOOK_VAULT_RETIRED_KEYS" => nil})
    assert Secrets.get("webhook") == nil
    assert Secrets.rotate() == 0
  end
end
