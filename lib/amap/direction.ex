defmodule Amap.Direction do
  @moduledoc """
  路径规划 — planning a way from one coordinate to another.

  Amap's v3 page (`guide/api/direction`). `walking/4` plans on foot, at most
  **100 km**, and answers paths ranked with Amap's own preference first.

  Both ends go in as `{lon, lat}` tuples and come back the same way — including
  every step's `polyline`, which Amap writes as one `;`-separated string and this
  module decodes into tuples, so no caller has to split it.
  """

  alias Amap.Coord
  alias Amap.Direction.Path
  alias Amap.Direction.Route
  alias Amap.Direction.Step
  alias Amap.Param
  alias Amap.Validate

  @walking_path "/v3/direction/walking"

  @doc """
  Plans a walking route.

  `origin` and `destination` are `{lon, lat}` tuples, at most six decimals.
  **Amap plans walking routes up to 100 km**; a longer pair is refused by the
  service rather than by this module.

  `:origin_id` and `:destination_id` are the POI ids of the two ends when they are
  known POIs, which Amap says improves the plan's accuracy. Note the underscores:
  this endpoint's page spells them `origin_id`/`destination_id`, while the driving
  endpoint's spells the same two parameters `originid`/`destinationid`.

  Returns the route Amap planned, or `%Amap.Direction.Route{paths: []}` when it
  found none — an answer with no `route` in it is not an error, and callers should
  not have to branch on a `nil` to enumerate paths. The number Amap also sends is
  not carried, since its length is the same thing.
  """
  @spec walking(Amap.Client.t(), {number(), number()}, {number(), number()}, keyword()) ::
          {:ok, Route.t()} | {:error, Amap.Error.t()}
  def walking(client, origin, destination, opts \\ []) do
    params = [
      origin: Param.location(Validate.point!(origin, ":origin")),
      destination: Param.location(Validate.point!(destination, ":destination")),
      origin_id: optional_poi_id(opts, :origin_id),
      destination_id: optional_poi_id(opts, :destination_id)
    ]

    case Amap.request(client, :restapi, :get, @walking_path, params) do
      {:ok, payload} -> {:ok, to_route(payload["route"])}
      {:error, _} = error -> error
    end
  end

  defp optional_poi_id(opts, key) do
    Validate.optional!(&Validate.present!/2, Keyword.get(opts, key), ":#{key}")
  end

  # Amap leaves `route` out entirely when it found nothing, which is an answer
  # rather than a failure: callers get an empty Route instead of a nil to branch on.
  defp to_route(nil), do: %Route{paths: []}

  defp to_route(payload) do
    %Route{
      origin: Coord.parse_location(payload["origin"]),
      destination: Coord.parse_location(payload["destination"]),
      taxi_cost: payload["taxi_cost"],
      paths: Enum.map(payload["paths"] || [], &to_path/1)
    }
  end

  defp to_path(payload) do
    %Path{
      distance: payload["distance"],
      duration: payload["duration"],
      strategy: payload["strategy"],
      tolls: payload["tolls"],
      restriction: payload["restriction"],
      traffic_lights: payload["traffic_lights"],
      toll_distance: payload["toll_distance"],
      steps: Enum.map(payload["steps"] || [], &to_step/1)
    }
  end

  defp to_step(payload) do
    %Step{
      instruction: payload["instruction"],
      road: payload["road"],
      distance: payload["distance"],
      orientation: payload["orientation"],
      duration: payload["duration"],
      polyline: Coord.parse_locations(payload["polyline"]),
      action: payload["action"],
      assistant_action: payload["assistant_action"],
      walk_type: payload["walk_type"],
      tolls: payload["tolls"],
      toll_distance: payload["toll_distance"],
      toll_road: payload["toll_road"]
    }
  end
end
