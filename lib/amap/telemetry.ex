defmodule Amap.Telemetry do
  @moduledoc """
  Telemetry around Amap calls.

  Uses `:telemetry.span/3`, so the usual `:start` / `:stop` / `:exception`
  events are emitted with `system_time` and `duration` measurements.

  Metadata is built from the request shape only. Credentials never appear.
  """

  alias Amap.{Client, Error}

  @prefix [:amap, :request]

  @doc """
  Runs `fun`, emitting `[:amap, :request, :start]` and
  `[:amap, :request, :stop]` around it.

  `fun` must return either `{:ok, payload}` or `{:error, %Amap.Error{}}`;
  the failure shape is what makes the stop metadata useful.
  """
  @spec span(Client.t(), Client.family(), :get | :post, String.t(), (-> result)) :: result
        when result: {:ok, term()} | {:error, Error.t()}
  def span(client, family, method, path, fun) do
    :telemetry.span(@prefix, start_meta(client, family, method, path), fn ->
      result = fun.()
      {result, stop_meta(result)}
    end)
  end

  @doc "Metadata for the start event."
  @spec start_meta(Client.t(), Client.family(), :get | :post, String.t()) :: map()
  def start_meta(%Client{} = client, family, method, path) do
    %{family: family, method: method, path: path, timeout: client.timeout}
  end

  @doc "Metadata for the stop event, derived from the call result."
  @spec stop_meta({:ok, term()} | {:error, Error.t()}) :: map()
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
