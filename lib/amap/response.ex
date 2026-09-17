defmodule Amap.Response do
  @moduledoc """
  Collapses Amap's two response envelopes into one payload shape.

  The Web service family answers with `{"status", "info", "infocode", …}` and
  flattens its results at the top level. The Falcon family answers with
  `{"errcode", "errmsg", "errdetail", "data"}`. After `normalize/3` callers see
  a bare payload map either way, so `Amap.Falcon.*` and `Amap.*` business
  modules never have to care which family they are talking to.
  """

  alias Amap.Client
  alias Amap.Error
  alias Amap.JSON
  alias Amap.Numeric

  @envelope_restapi ~w(status info infocode)
  @partial_success 20100

  @doc """
  Decodes a response body, returning the original binary when it is not JSON
  so the caller can report what the server actually sent.
  """
  @spec decode(binary()) :: {:ok, term()} | {:error, binary()}
  def decode(body) do
    case JSON.decode(body) do
      {:ok, term} -> {:ok, term}
      {:error, _reason} -> {:error, body}
    end
  end

  @doc """
  Validates an envelope and returns its payload.

  Falcon's `20100 PARTIAL_SUCCESS` is returned as `{:ok, data}`: the request
  was accepted and some of the work succeeded, so reporting it as an error
  would discard the successful part. Use `partial?/2` to detect it.
  """
  @spec normalize(Client.family(), term(), integer() | nil) ::
          {:ok, map() | nil} | {:error, Error.t()}
  def normalize(:tsapi, %{"errcode" => errcode} = body, http_status)
      when is_integer(errcode) or is_binary(errcode) do
    case Numeric.to_integer(errcode) do
      0 -> {:ok, Map.get(body, "data")}
      @partial_success -> {:ok, Map.get(body, "data")}
      nil -> {:error, Error.unexpected_response(http_status, body)}
      _other -> {:error, Error.from_tsapi(body, http_status)}
    end
  end

  def normalize(:restapi, %{"status" => "1"} = body, _http_status) do
    {:ok, Map.drop(body, @envelope_restapi)}
  end

  def normalize(:restapi, %{"status" => "0"} = body, http_status) do
    {:error, Error.from_restapi(body, http_status)}
  end

  def normalize(family, body, http_status) when family in [:restapi, :tsapi] do
    {:error, Error.unexpected_response(http_status, body)}
  end

  @doc "Whether a Falcon response reports partial success."
  @spec partial?(Client.family(), term()) :: boolean()
  def partial?(:tsapi, %{"errcode" => errcode}),
    do: Numeric.to_integer(errcode) == @partial_success

  def partial?(_family, _body), do: false
end
