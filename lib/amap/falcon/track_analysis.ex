defmodule Amap.Falcon.TrackAnalysis do
  @moduledoc """
  How a trajectory was driven, and where it stopped.

  Both endpoints read one trace. They are camelCase on the wire — `startTime`,
  `speedLimitThres`, `stayRadius` — while their options are snake_case like
  everywhere else in this SDK, and their windows take a `DateTime` or unix
  milliseconds.

  Neither endpoint is limited to a 24-hour window the way `Grasproad.trsearch/4`
  is: Amap reads the whole trace unless a window narrows it.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, policy} = Amap.Falcon.TrackAnalysis.driving_behavior(client, 1000, 456, 20)
      iex> policy.speed_limit.points
      []
      iex> {:ok, strict} =
      ...>   Amap.Falcon.TrackAnalysis.driving_behavior(client, 1000, 456, 20,
      ...>     speed_limit_thres: 80
      ...>   )
      iex> {strict.ave_speed, strict.harsh_acceleration_count}
      {48, 1}
      iex> [event] = strict.harsh_acceleration.points
      iex> {event.location, event.acceleration}
      {{114.1589, 22.2799}, 3.2}

  The options are snake_case while the parameters are camelCase: `speed_limit_thres: 80`
  reaches the wire as `speedLimitThres`, and the stand-in answers that call with a
  speeding section the default call does not get — leaving the thresholds out asks
  Amap for its own policy. A non-empty event list arrives one level deeper than an
  empty one, a live-observed shape this SDK flattens: `harsh_acceleration` holds its
  event while `harsh_deceleration` is an empty `%Section{}`.

  A payload that is not the endpoint's object is named rather than crashing inside
  the mapper, and the payload travels with the error so a caller can see what
  arrived:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:error, error} = Amap.Falcon.TrackAnalysis.driving_behavior(client, 1000, 456, 21)
      iex> {error.reason, error.response.body}
      {:unexpected_response, [%{"distance" => 1}, %{"distance" => 2}]}

  `stay_points/5` takes its own camelCase options, and a stay shorter than Amap's
  documented 60 seconds is refused before any request:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, stays} =
      ...>   Amap.Falcon.TrackAnalysis.stay_points(client, 1000, 456, 20,
      ...>     start_time: 1_789_703_117_430,
      ...>     stay_radius: 100,
      ...>     stay_time: 120,
      ...>     mode: :driving
      ...>   )
      iex> [stay] = stays.points
      iex> {stays.count, stay.location, stay.address}
      {1, {114.1589, 22.2799}, "香港中環"}
      iex> Amap.Falcon.TrackAnalysis.stay_points(client, 1000, 456, 20, stay_time: 59)
      ** (ArgumentError) :stay_time must be at least 60 seconds, got: 59
  """

  alias Amap.Error
  alias Amap.Falcon.TrackAnalysis.DrivingBehaviour
  alias Amap.Falcon.TrackAnalysis.Event
  alias Amap.Falcon.TrackAnalysis.Section
  alias Amap.Falcon.TrackAnalysis.StayPoint
  alias Amap.Falcon.TrackAnalysis.StayPoints
  alias Amap.Numeric
  alias Amap.Validate

  @base "/v1/track/analysis"

  @doc """
  Reports how a trace was driven.

  Returns the distance, the speeds, and the harsh events Amap found — acceleration,
  deceleration, steering and speeding — each as a list of points.

  The three thresholds are accelerations in m/s²; `speed_limit_thres` is in km/h,
  `30` to `120`. Leaving them out asks Amap for its own policy, which for speeding
  means the electronic speed limit of the road.
  """
  @spec driving_behavior(Amap.Client.t(), integer(), integer(), integer(), keyword()) ::
          {:ok, DrivingBehaviour.t() | nil} | {:error, Amap.Error.t()}
  def driving_behavior(client, sid, tid, trid, opts \\ []) do
    params =
      [sid: sid, tid: tid, trid: trid] ++
        window_params(opts) ++
        [
          accelerationThres: Keyword.get(opts, :acceleration_thres),
          decelerationThres: Keyword.get(opts, :deceleration_thres),
          steeringThres: Keyword.get(opts, :steering_thres),
          speedLimitThres: validate_speed_limit(Keyword.get(opts, :speed_limit_thres))
        ]

    case Amap.request(client, :tsapi, :get, @base <> "/drivingbehavior", params) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, payload} when is_map(payload) ->
        {:ok, to_behaviour(payload)}

      # Amap's pages say values arrive as strings or as arrays; a non-map here is a
      # shape this SDK does not recognise, and it becomes a named error carrying the
      # payload rather than a crash inside the mapper.
      {:ok, other} ->
        {:error, Error.unexpected_response(nil, other)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Reports where a trace stopped, with how long for and where.

  A stay is a period inside `stay_radius` metres — `5` to `500`, Amap's own default
  being 20 — lasting at least `stay_time` seconds, which Amap defaults to 600 and
  will not accept below 60.
  """
  @spec stay_points(Amap.Client.t(), integer(), integer(), integer(), keyword()) ::
          {:ok, StayPoints.t() | nil} | {:error, Amap.Error.t()}
  def stay_points(client, sid, tid, trid, opts \\ []) do
    params =
      [sid: sid, tid: tid, trid: trid] ++
        window_params(opts) ++
        [
          stayRadius:
            Validate.optional_range!(Keyword.get(opts, :stay_radius), ":stay_radius", 5, 500),
          stayTime: validate_stay_time(Keyword.get(opts, :stay_time)),
          mode: encode_mode(Keyword.get(opts, :mode))
        ]

    case Amap.request(client, :tsapi, :get, @base <> "/staypoint", params) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, payload} when is_map(payload) ->
        {:ok, to_stay_points(payload)}

      {:ok, other} ->
        {:error, Error.unexpected_response(nil, other)}

      {:error, _} = error ->
        error
    end
  end

  defp window_params(opts) do
    [
      startTime: to_ms(Keyword.get(opts, :start_time)),
      endTime: to_ms(Keyword.get(opts, :end_time))
    ]
  end

  defp to_ms(nil), do: nil
  defp to_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)
  defp to_ms(ms) when is_integer(ms), do: ms

  defp to_ms(other),
    do:
      raise(
        ArgumentError,
        "window times must be a DateTime or unix milliseconds, got: #{inspect(other)}"
      )

  defp validate_speed_limit(nil), do: nil

  defp validate_speed_limit(kmh),
    do: Validate.range!(kmh, ":speed_limit_thres", 30, 120)

  defp validate_stay_time(nil), do: nil

  defp validate_stay_time(seconds) when is_integer(seconds) and seconds >= 60, do: seconds

  defp validate_stay_time(other),
    do: raise(ArgumentError, ":stay_time must be at least 60 seconds, got: #{inspect(other)}")

  defp encode_mode(nil), do: nil
  defp encode_mode(:driving), do: "driving"

  defp encode_mode(other),
    do: raise(ArgumentError, ":mode must be :driving, got: #{inspect(other)}")

  # The four sections are the same shape with different measurement fields, so one
  # mapper serves all of them and an event that carries only its own section's
  # fields leaves the rest nil.
  defp to_behaviour(payload) do
    %DrivingBehaviour{
      distance: payload["distance"],
      duration: Numeric.to_integer(payload["duration"]),
      ave_speed: payload["aveSpeed"],
      max_speed: payload["maxSpeed"],
      harsh_acceleration_count: Numeric.to_integer(payload["harshAccelerationCount"]),
      harsh_deceleration_count: Numeric.to_integer(payload["harshDecelerationCount"]),
      harsh_steering_count: Numeric.to_integer(payload["harshSteeringCount"]),
      harsh_acceleration: to_section(payload["harshAcceleration"]),
      harsh_deceleration: to_section(payload["harshDeceleration"]),
      harsh_steering: to_section(payload["harshSteering"]),
      speed_limit: to_section(payload["speedLimit"])
    }
  end

  defp to_section(nil), do: nil

  defp to_section(payload) when is_map(payload) do
    # Amap nests a non-empty event list one level deeper than an empty one: a section
    # with events arrived as `%{"points" => [[event, event]]}` while an empty one
    # arrived as `%{"points" => []}`. Flattening reads both, and only descends into
    # lists, so maps pass through untouched. Collected with the other
    # page-versus-service differences collected on 2026-09-17.
    points = payload |> Map.get("points", []) |> List.flatten() |> Enum.map(&to_event/1)

    %Section{points: points}
  end

  defp to_event(payload) do
    %Event{
      location: Amap.Coord.parse_location(payload["location"]),
      locate_time: Numeric.to_integer(payload["locateTime"]),
      acceleration: payload["acceleration"],
      initial_speed: payload["initialSpeed"],
      end_speed: payload["endSpeed"],
      centripetal_acc: payload["centripetalAcc"],
      speed: payload["speed"],
      speed_limit: payload["speedLimit"]
    }
  end

  defp to_stay_points(payload) do
    %StayPoints{
      count: Numeric.to_integer(payload["stayPointCount"]),
      points: payload |> Map.get("stayPoints", []) |> List.flatten() |> Enum.map(&to_stay_point/1)
    }
  end

  defp to_stay_point(payload) do
    %StayPoint{
      start_time: Numeric.to_integer(payload["startTime"]),
      end_time: Numeric.to_integer(payload["endTime"]),
      duration: Numeric.to_integer(payload["duration"]),
      location: Amap.Coord.parse_location(payload["location"]),
      address: payload["address"]
    }
  end
end
