defmodule Amap.Client do
  @moduledoc """
  Configuration for a set of Amap API calls.

  A client is a plain struct with no associated process. Passing one around is
  free, and constructing one in a test is cheap.
  """

  @base_urls %{
    restapi: "https://restapi.amap.com",
    tsapi: "https://tsapi.amap.com"
  }

  @enforce_keys [:key]
  defstruct key: nil,
            private_key: nil,
            pool: Amap.Finch,
            limiter: nil,
            timeout: 5_000,
            retry: [],
            base_urls: @base_urls

  @type family :: :restapi | :tsapi

  @type t :: %__MODULE__{
          key: String.t(),
          private_key: String.t() | nil,
          pool: Finch.name(),
          limiter: pid() | nil,
          timeout: pos_integer(),
          retry: keyword(),
          base_urls: %{family() => String.t()}
        }

  @doc """
  The origin each API family is served from.

  Callers that need the default host — a test pointing at a local server, for
  instance — read it here rather than restating the URLs.
  """
  @spec default_base_urls() :: %{family() => String.t()}
  def default_base_urls, do: @base_urls
end
