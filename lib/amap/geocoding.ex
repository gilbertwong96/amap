defmodule Amap.Geocoding do
  @moduledoc """
  地理/逆地理编码 — a structured address to coordinates, and a coordinate back to
  an address.

  `geo/3` answers with the places an address might be, best match first. `regeo/3`
  is the reverse, and can also bring back the roads, intersections, POIs and AOIs
  around a point.

  Addresses are structured 国家、省份、城市、区县、城镇、乡村、街道、门牌号码 — country, province,
  city, district, town, village, street, house number: the country may be left out for
  the mainland, Hong Kong and Macao, but the province, city and district levels may not.
  Taiwan's detailed addresses are not served.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(
      ...>     key: "test-key",
      ...>     base_urls: %{restapi: "http://localhost:21617"}
      ...>   )
      iex> {:ok, base} = Amap.Geocoding.regeo(client, {116.31, 39.99})
      iex> {base.pois, base.roads}
      {[], []}
      iex> {:ok, detailed} =
      ...>   Amap.Geocoding.regeo(client, {116.31, 39.99}, extensions: :all)
      iex> Enum.map(detailed.pois, & &1.location)
      [{116.31, 39.991}]
      iex> Amap.Geocoding.regeo(client, {116.31, 39.99}, radius: 100)
      ** (ArgumentError) [:radius] only take effect with extensions: :all, which Amap otherwise ignores without saying so

  `extensions: :all` is what Amap asks for to send the detail rows; without it
  they arrive as `[]` rather than as `nil`, so a caller can enumerate them either
  way. The four options that only work with `:all` — `:radius`, `:poitype`,
  `:roadlevel`, `:homeorcorp` — are refused here, because Amap would silently
  ignore them and answer as if they had been applied.
  """

  alias Amap.Coord
  alias Amap.Geocoding.AddressComponent
  alias Amap.Geocoding.Aoi
  alias Amap.Geocoding.Building
  alias Amap.Geocoding.BusinessArea
  alias Amap.Geocoding.Geo
  alias Amap.Geocoding.Neighborhood
  alias Amap.Geocoding.Poi
  alias Amap.Geocoding.Regeo
  alias Amap.Geocoding.Road
  alias Amap.Geocoding.RoadInter
  alias Amap.Geocoding.StreetNumber
  alias Amap.Validate

  @geo_path "/v3/geocode/geo"
  @regeo_path "/v3/geocode/regeo"

  # Amap documents these four as taking effect only with `extensions=all`, and
  # ignores them silently otherwise — so a caller who sets one without the other
  # would get an answer that looks fine and is not what they asked for.
  @detail_options [:radius, :poitype, :roadlevel, :homeorcorp]

  @doc """
  Geocodes a structured address.

  `address` is 北京市朝阳区阜通东大街6号 (6 Futong East Street, Chaoyang, Beijing) or a landmark
  like 天安门 (Tiananmen). `:city` narrows
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
      city: Validate.optional_present!(Keyword.get(opts, :city), ":city")
    ]

    case Amap.request(client, :restapi, :get, @geo_path, params) do
      {:ok, payload} -> {:ok, Enum.map(payload["geocodes"] || [], &to_geo/1)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Reverse geocodes a coordinate.

  `location` is a `{lon, lat}` tuple, at most six decimals.

  `extensions: :all` is what brings back `roads`, `roadinters`, `pois` and `aois`
  — without it Amap omits them, and they arrive here as `[]` rather than as `nil`
  so a caller can always enumerate them. The four options that only work with
  `:all` (`:radius`, `:poitype`, `:roadlevel`, `:homeorcorp`) raise without it.

  `city` is **empty for the four municipalities** (北京/上海/天津/重庆 — Beijing, Shanghai,
  Tianjin, Chongqing) and for province-administered counties, so it is not a field to
  branch on. `sea_area` is the sea the point belongs to, if any.
  """
  @spec regeo(Amap.Client.t(), Amap.Coord.point(), keyword()) ::
          {:ok, Regeo.t()} | {:error, Amap.Error.t()}
  def regeo(client, location, opts \\ []) do
    params =
      [
        location: Amap.Param.location(location),
        extensions:
          Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base, :all])
      ] ++ detail_params(opts)

    case Amap.request(client, :restapi, :get, @regeo_path, params) do
      {:ok, payload} -> {:ok, to_regeo(payload["regeocode"] || %{})}
      {:error, _} = error -> error
    end
  end

  defp detail_params(opts) do
    given =
      opts
      |> Keyword.take(@detail_options)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Keyword.keys()

    if given != [] and Keyword.get(opts, :extensions) != :all do
      raise ArgumentError,
            "#{inspect(given)} only take effect with extensions: :all, which Amap " <>
              "otherwise ignores without saying so"
    end

    [
      radius: Validate.optional_range!(Keyword.get(opts, :radius), ":radius", 0, 3000),
      poitype: encode_poitype(Keyword.get(opts, :poitype)),
      roadlevel: Validate.optional_range!(Keyword.get(opts, :roadlevel), ":roadlevel", 0, 1),
      homeorcorp: Validate.optional_range!(Keyword.get(opts, :homeorcorp), ":homeorcorp", 0, 2)
    ]
  end

  defp encode_poitype(nil), do: nil
  defp encode_poitype(type) when is_binary(type), do: type
  defp encode_poitype(types) when is_list(types), do: Amap.Param.pipe(types)

  defp encode_poitype(other),
    do:
      raise(
        ArgumentError,
        ":poitype must be a TYPECODE or a list of them, got: #{inspect(other)}"
      )

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

  defp to_regeo(payload) do
    %Regeo{
      address_component: to_address_component(payload["addressComponent"]),
      roads: Enum.map(payload["roads"] || [], &to_road/1),
      roadinters: Enum.map(payload["roadinters"] || [], &to_road_inter/1),
      pois: Enum.map(payload["pois"] || [], &to_poi/1),
      aois: Enum.map(payload["aois"] || [], &to_aoi/1)
    }
  end

  defp to_address_component(nil), do: nil

  defp to_address_component(payload) do
    %AddressComponent{
      country: payload["country"],
      province: payload["province"],
      city: payload["city"],
      citycode: payload["citycode"],
      district: payload["district"],
      adcode: payload["adcode"],
      township: payload["township"],
      towncode: payload["towncode"],
      neighborhood: to_neighborhood(payload["neighborhood"]),
      building: to_building(payload["building"]),
      street_number: to_street_number(payload["streetNumber"]),
      sea_area: payload["seaArea"],
      business_areas: Enum.map(payload["businessAreas"] || [], &to_business_area/1)
    }
  end

  defp to_neighborhood(nil), do: nil

  defp to_neighborhood(payload) do
    %Neighborhood{name: payload["name"], type: payload["type"]}
  end

  defp to_building(nil), do: nil

  defp to_building(payload) do
    %Building{name: payload["name"], type: payload["type"]}
  end

  defp to_street_number(nil), do: nil

  defp to_street_number(payload) do
    %StreetNumber{
      street: payload["street"],
      number: payload["number"],
      location: Coord.parse_location(payload["location"]),
      direction: payload["direction"],
      distance: payload["distance"]
    }
  end

  defp to_business_area(payload) do
    %BusinessArea{
      location: Coord.parse_location(payload["location"]),
      name: payload["name"],
      id: payload["id"]
    }
  end

  defp to_road(payload) do
    %Road{
      id: payload["id"],
      name: payload["name"],
      distance: payload["distance"],
      direction: payload["direction"],
      location: Coord.parse_location(payload["location"])
    }
  end

  defp to_road_inter(payload) do
    %RoadInter{
      distance: payload["distance"],
      direction: payload["direction"],
      location: Coord.parse_location(payload["location"]),
      first_id: payload["first_id"],
      first_name: payload["first_name"],
      second_id: payload["second_id"],
      second_name: payload["second_name"]
    }
  end

  defp to_poi(payload) do
    %Poi{
      id: payload["id"],
      name: payload["name"],
      type: payload["type"],
      tel: payload["tel"],
      distance: payload["distance"],
      direction: payload["direction"],
      address: payload["address"],
      location: Coord.parse_location(payload["location"]),
      businessarea: payload["businessarea"]
    }
  end

  defp to_aoi(payload) do
    %Aoi{
      id: payload["id"],
      name: payload["name"],
      adcode: payload["adcode"],
      location: Coord.parse_location(payload["location"]),
      area: payload["area"],
      distance: payload["distance"],
      type: payload["type"]
    }
  end
end
