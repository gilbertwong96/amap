defmodule Amap.Response do
  @moduledoc """
  Collapses Amap's two response envelopes into one payload shape.

  The Web service family answers with `{"status", "info", "infocode", …}` and
  flattens its results at the top level. The Falcon family answers with
  `{"errcode", "errmsg", "errdetail", "data"}`. After `normalize/3` callers see
  a bare payload map either way, so `Amap.Falcon.*` and `Amap.*` business
  modules never have to care which family they are talking to.

  智能硬件定位 v1 (`apilocate.amap.com`) answers a third shape: `status`/`info`
  around a `result`, with **no `infocode` row at all** and symbolic `info`
  values, so its failures carry the text and no code.

  For the flat envelope it also applies Amap's empty-array convention, so that a
  field with no value reaches a caller as `nil` rather than as `[]` — the rule
  its own pages state — 当返回值不存在时，则以数组类型返回, "a value that is absent comes back as
  an array" — and the one this SDK promises for every struct field.
  """

  alias Amap.Error
  alias Amap.JSON
  alias Amap.Numeric

  @typedoc "An envelope `normalize/3` parses."
  @type envelope :: :restapi | :tsapi | :apilocate

  @envelope_restapi ~w(status info infocode)
  # 智能硬件定位 v1 has no infocode row; status and info are the whole envelope.
  @envelope_apilocate ~w(status info)
  # Falcon signals success with 10000 (`10000 OK` is the error table's first
  # row) and the documented examples also use 0. Accepting only 0 turned every
  # successful Falcon call into an error once the payload had already been
  # carried out on Amap's side.
  @ok_codes [0, 10_000]
  @partial_success 20100

  @typedoc """
  The payload a call answers with, once either envelope has been taken apart.

  A Web-service response is an object; a Falcon `data` body is whatever that
  endpoint returns — an object, an array of rows, or nothing at all for the
  write-only calls.
  """
  @type payload :: Amap.JSON.object() | [Amap.JSON.value()] | nil

  @doc """
  Decodes a response body, returning the original binary when it is not JSON
  so the caller can report what the server actually sent.
  """
  @spec decode(binary()) :: {:ok, Amap.JSON.value()} | {:error, binary()}
  def decode(body) do
    case JSON.decode(body) do
      {:ok, term} -> {:ok, term}
      {:error, _reason} -> {:error, body}
    end
  end

  @doc """
  Validates an envelope and returns its payload.

  Falcon signals success with `10000`, which the live API really sends —
  `{"errcode": 10000, "errmsg": "OK", "data": …}` — and the documented error
  table lists it as the first row, `10000 OK`. The examples in some pages use
  `0`, so both are accepted. Treating only `0` as success made every real Falcon
  call look like a failure while Amap had already carried it out.

  Falcon's `20100 PARTIAL_SUCCESS` is returned as `{:ok, data}`: the request
  was accepted and some of the work succeeded, so reporting it as an error
  would discard the successful part. Use `partial?/2` to detect it.
  """
  @spec normalize(envelope(), Amap.JSON.value(), integer() | nil) ::
          {:ok, payload()} | {:error, Error.t()}
  def normalize(:tsapi, %{"errcode" => errcode} = body, http_status)
      when is_integer(errcode) or is_binary(errcode) do
    case Numeric.to_integer(errcode) do
      code when code in @ok_codes -> {:ok, unwrap_data(body)}
      @partial_success -> {:ok, unwrap_data(body)}
      nil -> {:error, Error.unexpected_response(http_status, body)}
      _other -> {:error, Error.from_tsapi(body, http_status)}
    end
  end

  def normalize(:restapi, %{"status" => "1"} = body, _http_status) do
    {:ok, empty_to_nil(Map.drop(body, @envelope_restapi))}
  end

  def normalize(:restapi, %{"status" => "0"} = body, http_status) do
    {:error, Error.from_restapi(body, http_status)}
  end

  # The 智能硬件定位 v1 envelope, which has no infocode row and symbolic info
  # values. Success keeps whatever `result` carries — the page calls it a list but
  # nests scalars, and no sample body exists — and a failure keeps the info text
  # with no code, since there is no numeric table to classify it by.
  def normalize(:apilocate, %{"status" => "1"} = body, _http_status) do
    {:ok, empty_to_nil(Map.drop(body, @envelope_apilocate))}
  end

  def normalize(:apilocate, %{"status" => "0"} = body, http_status) do
    {:error, Error.from_apilocate(body, http_status)}
  end

  def normalize(:apilocate, body, http_status) do
    {:error, Error.unexpected_response(http_status, body)}
  end

  def normalize(envelope, body, http_status) when envelope in [:restapi, :tsapi] do
    {:error, Error.unexpected_response(http_status, body)}
  end

  # Amap writes "no value" as an empty array rather than omitting the field — its own
  # pages say so: 当返回值不存在时，则以数组类型返回 ("a value that is absent comes back as an
  # array") — and it wraps a single object in an array the same way. The analysis
  # endpoints answered `data: [%{…}]` live on 2026-09-17 while their own tables describe
  # an object, so an array is read as a wrapper: one element is that element, none is no
  # data. Collected with the other page-versus-service differences on 2026-09-17.
  defp unwrap_data(%{"data" => []}), do: nil
  defp unwrap_data(%{"data" => [single]}), do: single
  defp unwrap_data(body), do: Map.get(body, "data")

  # The flat envelope writes "no value" as an empty array — `/v3/ip` reports four
  # of them for an address it cannot place — so the whole payload is walked once
  # here rather than every mapper remembering. A field that means one value, or a
  # collection that means nothing, both arrive as nil; a mapper that wants an
  # enumerable collection reads `payload["roads"] || []`.
  defp empty_to_nil(value) when is_list(value) do
    case Enum.map(value, &empty_to_nil/1) do
      [] -> nil
      items -> items
    end
  end

  defp empty_to_nil(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {key, empty_to_nil(item)} end)
  end

  defp empty_to_nil(value), do: value

  @doc "Whether a Falcon response reports partial success."
  @spec partial?(:tsapi, Amap.JSON.value()) :: boolean()
  def partial?(:tsapi, %{"errcode" => errcode}),
    do: Numeric.to_integer(errcode) == @partial_success

  def partial?(_family, _body), do: false
end
