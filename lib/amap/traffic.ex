defmodule Amap.Traffic do
  @moduledoc """
  交通态势查询 — how the traffic is flowing, along a road, inside a circle or inside a
  rectangle.

  **This is a 高级服务 (premium) interface.** Amap opens it case by case — the page
  asks you to 商务咨询, to ask commercially — so a key that has not applied for it is
  answered with a refusal while its other calls keep working. It also covers **40
  named cities** rather than the whole country, so a query outside them fails for a
  reason that has nothing to do with how it was written.

  All three endpoints take a `level`, the road classes to read: 1 高速 (expressway),
  2 城市快速路/国道 (urban expressway or national road), 3 高速辅路 (expressway service
  road), 4 主要道路 (major road), 5 一般道路 (ordinary road) and 6 无名道路 (unnamed
  road). **The values nest** — asking for 5 brings back 1 to 4 as well — so a level
  says how far down the hierarchy to look, not which single class to read.
  """

  alias Amap.Param
  alias Amap.Traffic.Evaluation
  alias Amap.Traffic.Road
  alias Amap.Validate

  @road_path "/v3/traffic/status/road"
  @circle_path "/v3/traffic/status/circle"
  @rectangle_path "/v3/traffic/status/rectangle"
  @max_radius 4999

  defstruct [:description, evaluation: nil, roads: []]

  @type t :: %__MODULE__{
          description: String.t() | nil,
          evaluation: Evaluation.t() | nil,
          roads: [Road.t()]
        }

  @doc """
  Reads the traffic on one named road.

  `name` is the road's name and `:city` or `:adcode` must be given — Amap itself
  recommends the `adcode`, because `:city` has to match its own naming (深圳市, not
  深圳). Roads come back with `extensions: :all` only.
  """
  @spec road(Amap.Client.t(), integer(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def road(client, level, name, opts \\ []) do
    reject_missing_city!(opts)

    params = [
      level: validate_level!(level),
      name: Validate.present!(name, ":name"),
      city: Validate.optional_present!(Keyword.get(opts, :city), ":city"),
      adcode: Validate.optional_present!(Keyword.get(opts, :adcode), ":adcode")
    ]

    request(client, @road_path, params ++ common_params(opts))
  end

  @doc """
  Reads the traffic inside a circle.

  `location` is a `{lon, lat}` tuple. `:radius` is in metres, at most 4999 and with
  no decimals; Amap's own default is 1000.
  """
  @spec circle(Amap.Client.t(), integer(), {number(), number()}, keyword()) ::
          {:ok, t()} | {:error, Amap.Error.t()}
  def circle(client, level, location, opts \\ []) do
    params = [
      level: validate_level!(level),
      location: Param.location(location),
      radius: Validate.optional_range!(Keyword.get(opts, :radius), ":radius", 1, @max_radius)
    ]

    request(client, @circle_path, params ++ common_params(opts))
  end

  @doc """
  Reads the traffic inside a rectangle.

  `rectangle` is two `{lon, lat}` corners, the lower-left one first. Amap refuses a
  rectangle whose diagonal is longer than 10 km, which this cannot check.
  """
  @spec rectangle(
          Amap.Client.t(),
          integer(),
          {{number(), number()}, {number(), number()}},
          keyword()
        ) :: {:ok, t()} | {:error, Amap.Error.t()}
  def rectangle(client, level, rectangle, opts \\ []) do
    params = [
      level: validate_level!(level),
      rectangle: encode_rectangle!(rectangle)
    ]

    request(client, @rectangle_path, params ++ common_params(opts))
  end

  defp request(client, path, params) do
    case Amap.request(client, :restapi, :get, path, params) do
      {:ok, payload} -> {:ok, to_traffic(payload["trafficinfo"] || %{})}
      {:error, _} = error -> error
    end
  end

  defp common_params(opts) do
    [
      extensions:
        Validate.optional_enum!(Keyword.get(opts, :extensions), ":extensions", [:base, :all])
    ]
  end

  defp reject_missing_city!(opts) do
    if is_nil(Keyword.get(opts, :city)) and is_nil(Keyword.get(opts, :adcode)) do
      raise ArgumentError, ":city or :adcode is required: Amap takes one of the two"
    end
  end

  defp validate_level!(level), do: Validate.range!(level, ":level", 1, 6)

  # The two corners are one `;`-separated string on the wire, which is exactly what
  # `Param.locations/1` builds — the endpoint whose request *does* want `;`.
  defp encode_rectangle!({{_, _} = lower_left, {_, _} = upper_right}) do
    [left, right] = [
      Validate.point!(lower_left, ":rectangle"),
      Validate.point!(upper_right, ":rectangle")
    ]

    Param.locations([left, right])
  end

  defp encode_rectangle!(other),
    do:
      raise(
        ArgumentError,
        ":rectangle must be two {lon, lat} corners, got: #{inspect(other)}"
      )

  defp to_traffic(payload) do
    %__MODULE__{
      description: payload["description"],
      evaluation: to_evaluation(payload["evaluation"]),
      roads: Enum.map(payload["roads"] || [], &to_road/1)
    }
  end

  defp to_evaluation(nil), do: nil

  defp to_evaluation(payload) do
    %Evaluation{
      expedite: payload["expedite"],
      congested: payload["congested"],
      blocked: payload["blocked"],
      unknown: payload["unknown"]
    }
  end

  defp to_road(payload) do
    %Road{
      name: payload["name"],
      status: payload["status"],
      direction: payload["direction"],
      angle: payload["angle"],
      lcodes: payload["lcodes"],
      speed: payload["speed"],
      polyline: Amap.Coord.parse_locations(payload["polyline"])
    }
  end
end
