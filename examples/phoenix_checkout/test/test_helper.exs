ExUnit.start()

migrations_path = Path.expand("../priv/repo/migrations", __DIR__)
Ecto.Migrator.run(DodoStore.Repo, migrations_path, :up, all: true)
Ecto.Adapters.SQL.Sandbox.mode(DodoStore.Repo, :manual)
