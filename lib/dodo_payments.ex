defmodule DodoPayments do
  @moduledoc """
  Req-first Elixir SDK for Dodo Payments.

  Construct an explicit `DodoPayments.Client` and pass it as the first argument
  to Dodo-named resource modules such as `DodoPayments.CheckoutSessions`,
  `DodoPayments.Payments`, and `DodoPayments.Subscriptions`.

      client =
        DodoPayments.client!(
          environment: :test,
          api_key: System.fetch_env!("DODO_PAYMENTS_API_KEY")
        )

      DodoPayments.Products.list(client)

  No application-global API key or SDK-owned process is required.
  """

  @version_file Path.expand("../VERSION", __DIR__)
  @external_resource @version_file
  @version @version_file |> File.read!() |> String.trim()
  @type json ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json()]
          | %{optional(String.t()) => json()}

  @doc "Delegates to `DodoPayments.Client.new/1`."
  @spec client(keyword()) ::
          {:ok, DodoPayments.Client.t()} | {:error, DodoPayments.Error.ConfigurationError.t()}
  defdelegate client(options \\ []), to: DodoPayments.Client, as: :new

  @doc "Delegates to `DodoPayments.Client.new!/1`."
  @spec client!(keyword()) :: DodoPayments.Client.t()
  defdelegate client!(options \\ []), to: DodoPayments.Client, as: :new!

  @doc """
  Returns successful data or raises the returned SDK exception.

      iex> DodoPayments.unwrap!({:ok, :paid})
      :paid
  """
  @spec unwrap!({:ok, value} | {:error, Exception.t()}) :: value when value: term()
  def unwrap!({:ok, value}), do: value
  def unwrap!({:error, %_{} = exception}), do: raise(exception)

  @doc "Version of the audited official Dodo Payments SDK source surface."
  @spec source_sdk_version() :: String.t()
  defdelegate source_sdk_version(), to: DodoPayments.SourceMetadata

  @doc "Number of classified merchant/public HTTP operations in this SDK."
  @spec operation_count() :: pos_integer()
  defdelegate operation_count(), to: DodoPayments.SourceMetadata

  @doc "HTTP user-agent emitted by this SDK release."
  @spec user_agent() :: String.t()
  def user_agent, do: "dodo-payments-elixir/" <> @version

  @doc "Version of this Elixir SDK release."
  @spec version() :: String.t()
  def version, do: @version
end
