defmodule Amap.IpLocation do
  @moduledoc """
  IP 定位 — where an address is.

  `province` and `city` name a municipality as itself (北京, Beijing, appears in both), and a
  LAN address reports `局域网` (a local network) as its province. An address Amap cannot
  place —
  an illegal one, or a foreign one — reports **nothing**: its four fields arrive
  as empty arrays, which is the behaviour this SDK normalises to `nil`
  everywhere, and the first one we ever saw.

  Amap resolves **IPv4 in China only**. An IPv6 literal is a call-site error
  rather than a round trip, so it raises here.
  """

  alias Amap.Coord

  @path "/v3/ip"

  defstruct [:province, :city, :adcode, :rectangle]

  @type t :: %__MODULE__{
          province: String.t() | nil,
          city: String.t() | nil,
          adcode: String.t() | nil,
          rectangle: [{float(), float()}] | nil
        }

  @doc """
  Locates an IP address, or the caller's own when none is given.

  `rectangle` is the city's bounding box as two points, lower-left then
  upper-right, and `adcode` is the **city's** code rather than the province's.
  """
  @spec ip(Amap.Client.t(), keyword()) :: {:ok, t()} | {:error, Amap.Error.t()}
  def ip(client, opts \\ []) do
    params = [ip: validate_address!(Keyword.get(opts, :ip))]

    case Amap.request(client, :restapi, :get, @path, params) do
      {:ok, payload} -> {:ok, to_ip_location(payload)}
      {:error, _} = error -> error
    end
  end

  defp validate_address!(nil), do: nil

  defp validate_address!(address) when is_binary(address) do
    case :inet.parse_ipv4_address(String.to_charlist(address)) do
      {:ok, _} -> address
      {:error, _} -> raise ArgumentError, ip_message(address)
    end
  end

  defp validate_address!(other), do: raise(ArgumentError, ip_message(other))

  defp ip_message(value), do: ":ip must be an IPv4 address, got: #{inspect(value)}"

  defp to_ip_location(payload) do
    %__MODULE__{
      province: payload["province"],
      city: payload["city"],
      adcode: payload["adcode"],
      rectangle: Coord.parse_locations(payload["rectangle"])
    }
  end
end
