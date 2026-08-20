Mix.Task.run("app.start")

case DodoStore.ProductSetup.ensure_product() do
  {:ok, product, :created} ->
    IO.puts("Created #{product.name} in Dodo Payments #{DodoStore.Dodo.mode()} mode.")
    IO.puts("Product ID: #{product.product_id}")
    IO.puts("Saved the ID to tmp/dodo_product_id.")

  {:ok, product, :existing} ->
    IO.puts("Using existing Dodo product #{product.name} (#{product.product_id}).")

  {:error, %DodoPayments.Error.OutcomeUnknown{} = error} ->
    IO.puts(:stderr, Exception.message(error))
    IO.puts(:stderr, "Do not rerun immediately. Reconcile the product in Dodo first.")
    System.halt(1)

  {:error, {:product_created_but_not_saved, product_id, reason}} ->
    IO.puts(:stderr, "Dodo created product #{product_id}, but its ID could not be saved locally.")
    IO.puts(:stderr, "Persistence error: #{inspect(reason)}")
    IO.puts(:stderr, "Set DODO_PRODUCT_ID=#{product_id} before running the setup script again.")
    System.halt(1)

  {:error, {:setup_locked, lock_path}} ->
    IO.puts(:stderr, "Another product setup owns #{lock_path}.")

    IO.puts(
      :stderr,
      "Wait for it to finish. If it crashed, remove that stale lock directory manually."
    )

    System.halt(1)

  {:error, error} when is_exception(error) ->
    IO.puts(:stderr, Exception.message(error))
    System.halt(1)

  {:error, reason} ->
    IO.puts(:stderr, inspect(reason))
    System.halt(1)
end
