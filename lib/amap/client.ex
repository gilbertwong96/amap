defmodule Amap.Client do
  @moduledoc """
  Configuration for a set of Amap API calls.

  A client is a plain struct with no associated process. Passing one around is
  free, and constructing one in a test is cheap.

  ## Examples

  The example is a doctest: it runs against a local stand-in, so it needs no key
  and never calls Amap.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{restapi: "http://localhost:21617"})
      iex> client.base_urls
      %{restapi: "http://localhost:21617"}
      iex> {:ok, payload} = Amap.request(client, :restapi, :get, "/v3/ip", [])
      iex> payload["province"]
      "北京市"

  `base_urls` is the copy of each host's origin that a call resolves against, and
  overriding one host is how it is pointed at a proxy or a local server; a host the
  map omits keeps the value `default_base_urls/0` gives it. A real call site omits
  `base_urls` entirely — `Amap.new(key: …)` — and the override is also the seam the
  doctests in this SDK's documentation run on: the local stand-in answers on that
  port, so the examples never need a key or reach Amap.
  """

  @enforce_keys [:key]
  defstruct key: nil,
            private_key: nil,
            pool: Amap.Finch,
            limiter: nil,
            timeout: 5_000,
            retry: [],
            base_urls: Amap.Host.default_base_urls()

  @type t :: %__MODULE__{
          key: String.t(),
          private_key: String.t() | nil,
          pool: Finch.name(),
          limiter: pid() | nil,
          timeout: pos_integer(),
          retry: keyword(),
          base_urls: %{Amap.Host.name() => String.t()}
        }

  @doc """
  The origin each host is served from.

  A client carries a copy so callers can point one at a proxy or a local test
  server; this is where the defaults come from, and `Amap.Host` remains the one
  place the wire facts are stated.
  """
  @spec default_base_urls() :: %{Amap.Host.name() => String.t()}
  def default_base_urls, do: Amap.Host.default_base_urls()
end
