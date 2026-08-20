defmodule DodoStoreWeb.CacheBodyReader do
  @moduledoc false

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()}
          | {:more, binary(), Plug.Conn.t()}
          | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, cache(conn, body)}
      {:more, body, conn} -> read_more(conn, opts, [body])
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_more(conn, opts, chunks) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        raw_body = chunks |> Enum.reverse([body]) |> IO.iodata_to_binary()
        {:ok, raw_body, cache(conn, raw_body)}

      {:more, body, conn} ->
        read_more(conn, opts, [body | chunks])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cache(conn, body), do: Plug.Conn.put_private(conn, :raw_body, body)
end
