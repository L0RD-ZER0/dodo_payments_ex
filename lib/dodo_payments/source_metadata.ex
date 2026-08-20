defmodule DodoPayments.SourceMetadata do
  @moduledoc false

  @source_lock Path.expand("../../priv/upstream/source-lock.json", __DIR__)
  @external_resource @source_lock
  @metadata @source_lock |> File.read!() |> Jason.decode!()

  @source_sdk_version Map.fetch!(@metadata, "version")
  @operation_count Map.fetch!(@metadata, "sdk_core_operation_total")

  @spec source_sdk_version() :: String.t()
  def source_sdk_version, do: @source_sdk_version

  @spec operation_count() :: pos_integer()
  def operation_count, do: @operation_count
end
