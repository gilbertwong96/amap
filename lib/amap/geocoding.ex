defmodule Amap.Geocoding do
  @moduledoc """
  地理/逆地理编码 — a structured address to coordinates, and a coordinate back to
  an address.

  `geo/3` answers with the places an address might be, best match first. `regeo/3`
  is the reverse, and can also bring back the roads, intersections, POIs and AOIs
  around a point.

  Addresses are structured 国家、省份、城市、区县、城镇、乡村、街道、门牌号码: the
  country may be left out for the mainland, Hong Kong and Macao, but the province,
  city and district levels may not. Taiwan's detailed addresses are not served.
  """

  alias Amap.Coord
  alias Amap.Geocoding.Geo
  alias Amap.Validate

  @geo_path "/v3/geocode/geo"

  @doc """
  Geocodes a structured address.

  `address` is 北京市朝阳区阜通东大街6号 or a landmark like 天安门. `:city` narrows
  the search and may be a Chinese name, its pinyin, a `citycode` or an `adcode`;
  **county-level cities are not supported**, and leaving it out searches the whole
  country.

  Returns the matches Amap ranked, as a list — `[]` when there are none. The
  number Amap also sends is not carried, since its length is the same thing.
  """
  @spec geo(Amap.Client.t(), String.t(), keyword()) ::
          {:ok, [Geo.t()]} | {:error, Amap.Error.t()}
  def geo(client, address, opts \\ []) do
    params = [
      address: Validate.present!(address, ":address"),
      city: Validate.optional!(&Validate.present!/2, Keyword.get(opts, :city), ":city")
    ]

    case Amap.request(client, :restapi, :get, @geo_path, params) do
      {:ok, payload} -> {:ok, Enum.map(payload["geocodes"] || [], &to_geo/1)}
      {:error, _} = error -> error
    end
  end

  defp to_geo(payload) do
    %Geo{
      country: payload["country"],
      province: payload["province"],
      city: payload["city"],
      citycode: payload["citycode"],
      district: payload["district"],
      street: payload["street"],
      number: payload["number"],
      adcode: payload["adcode"],
      location: Coord.parse_location(payload["location"]),
      level: payload["level"]
    }
  end
end
