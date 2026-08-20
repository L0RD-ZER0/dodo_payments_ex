defmodule DodoPayments.Secret do
  @moduledoc "Opaque, redacted storage for an API key or runtime key provider."

  @enforce_keys [:source]
  defstruct [:source]

  @type source :: String.t() | (-> String.t() | nil)
  @opaque t :: %__MODULE__{source: source()}

  @doc false
  @spec new(source() | nil) :: t() | nil
  def new(nil), do: nil
  def new(value) when is_binary(value) or is_function(value, 0), do: %__MODULE__{source: value}

  @doc false
  @spec valid_value?(term()) :: boolean()
  def valid_value?(value) when is_binary(value) and byte_size(value) > 0 do
    Enum.all?(:binary.bin_to_list(value), fn
      9 -> true
      byte when byte in 32..126 -> true
      _byte -> false
    end)
  end

  def valid_value?(_value), do: false

  @doc false
  @spec resolve(t() | nil) :: {:ok, String.t()} | {:error, Exception.t()}
  def resolve(nil) do
    {:error,
     DodoPayments.Error.ConfigurationError.exception(
       message: "this operation requires an API key"
     )}
  end

  def resolve(%__MODULE__{source: value}) when is_binary(value), do: validate(value)

  def resolve(%__MODULE__{source: provider}) when is_function(provider, 0) do
    try do
      provider.() |> validate()
    rescue
      exception ->
        {:error,
         DodoPayments.Error.PreparationError.exception(
           operation: :api_key_provider,
           kind: :error,
           cause: exception,
           stacktrace: __STACKTRACE__
         )}
    catch
      kind, reason ->
        {:error,
         DodoPayments.Error.PreparationError.exception(
           operation: :api_key_provider,
           kind: kind,
           cause: reason,
           stacktrace: __STACKTRACE__
         )}
    end
  end

  defp validate(value) when is_binary(value) do
    if valid_value?(value), do: {:ok, value}, else: invalid_key()
  end

  defp validate(_), do: invalid_key()

  defp invalid_key do
    {:error,
     DodoPayments.Error.ConfigurationError.exception(
       message: "API key must be a non-empty ASCII string without HTTP control bytes"
     )}
  end
end

defimpl Inspect, for: DodoPayments.Secret do
  def inspect(_secret, _opts), do: "#DodoPayments.Secret<redacted>"
end
