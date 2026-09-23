defmodule Amap.Telemetry do
  @moduledoc """
  Telemetry around Amap calls.

  Uses `:telemetry.span/3`, so the usual `:start` / `:stop` / `:exception`
  events are emitted with `system_time` and `duration` measurements.

  Metadata is built from the request shape only. Credentials never appear.
  """

  alias Amap.{Client, Error, Host}

  @prefix [:amap, :request]

  @typedoc "The metadata emitted with `[:amap, :request, :start]`."
  @type start_metadata :: %{
          host: Host.name(),
          method: Amap.Request.method(),
          path: String.t(),
          timeout: pos_integer()
        }

  @typedoc "The metadata emitted with `[:amap, :request, :stop]`."
  @type stop_metadata ::
          %{result: :ok}
          | %{
              result: :error,
              reason: atom(),
              code: integer() | nil,
              family: Host.envelope() | nil,
              http_status: integer() | nil,
              retry: :no | :immediate | :backoff
            }

  @doc """
  Runs `fun`, emitting `[:amap, :request, :start]` and
  `[:amap, :request, :stop]` around it.

  `fun` must return either `{:ok, payload}` or `{:error, %Amap.Error{}}`;
  the failure shape is what makes the stop metadata useful.
  """
  @spec span(Client.t(), Host.name(), Amap.Request.method(), String.t(), (-> result)) :: result
        when result: {:ok, Amap.JSON.value()} | {:error, Error.t()}
  def span(client, host, method, path, fun) do
    :telemetry.span(@prefix, start_meta(client, host, method, path), fn ->
      result = fun.()
      {result, stop_meta(result)}
    end)
  end

  @doc "Metadata for the start event."
  @spec start_meta(Client.t(), Host.name(), Amap.Request.method(), String.t()) :: start_metadata()
  def start_meta(%Client{} = client, host, method, path) do
    %{host: host, method: method, path: path, timeout: client.timeout}
  end

  @doc "Metadata for the stop event, derived from the call result."
  @spec stop_meta({:ok, Amap.JSON.value()} | {:error, Error.t()}) :: stop_metadata()
  def stop_meta({:ok, _payload}), do: %{result: :ok}

  def stop_meta({:error, %Error{} = error}) do
    %{
      result: :error,
      reason: error.reason,
      code: error.code,
      family: error.family,
      http_status: error.http_status,
      retry: error.retry
    }
  end
end
