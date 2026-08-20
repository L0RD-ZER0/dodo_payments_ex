defmodule DodoStore.Smoke.SecretSafe do
  @moduledoc false

  @forbidden_keys ~w(
    api_key authorization bearer_token capability_url checkout_url client_secret
    document_url payment_link portal_url secret signed_url webhook_secret
    webhook_secrets
  )

  @spec check(term()) :: :ok | {:error, String.t()}
  def check(value), do: check(value, [])

  defp check(value, path) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {key, nested}, :ok ->
      normalized_key = key |> to_string() |> String.downcase()
      next_path = path ++ [normalized_key]

      if forbidden_key?(normalized_key) do
        {:halt, {:error, Enum.join(next_path, ".")}}
      else
        case check(nested, next_path) do
          :ok -> {:cont, :ok}
          {:error, _path} = error -> {:halt, error}
        end
      end
    end)
  end

  defp check(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {nested, index}, :ok ->
      case check(nested, path ++ [Integer.to_string(index)]) do
        :ok -> {:cont, :ok}
        {:error, _path} = error -> {:halt, error}
      end
    end)
  end

  defp check(value, path) when is_binary(value) do
    if secret_value?(value), do: {:error, Enum.join(path, ".")}, else: :ok
  end

  defp check(_value, _path), do: :ok

  defp forbidden_key?(key) do
    key in @forbidden_keys or
      key == "url" or
      String.ends_with?(key, ["_api_key", "_client_secret", "_webhook_secret", "_url"])
  end

  defp secret_value?(value) do
    String.starts_with?(value, ["dodo_test_", "dodo_live_", "whsec_", "Bearer "])
  end
end
