defmodule DodoPayments.ClientModule do
  @moduledoc """
  The small, replaceable HTTP boundary used by `DodoPayments.Client`.

  An implementation receives a fully prepared request and performs **exactly one**
  network attempt. Authentication, retries, decoding, deadlines, telemetry, and
  Dodo-specific safety policy belong to the SDK request engine.

  Custom implementations may use Tesla or an internal HTTP stack. Adapter state is
  created by the application and stored in the immutable client value; the SDK does
  not start an adapter process.
  """

  alias DodoPayments.HTTP.{Request, Response, TransportError}

  @type state :: term()
  @type result :: {:ok, Response.t()} | {:error, TransportError.t()}

  @callback request(state(), Request.t()) :: result()
end
