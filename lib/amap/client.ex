defmodule Amap.Client do
  @moduledoc """
  Configuration for a set of Amap API calls.

  A client is a plain struct with no associated process. Passing one around is
  free, and constructing one in a test is cheap.
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
