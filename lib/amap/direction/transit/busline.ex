defmodule Amap.Direction.Transit.Busline do
  @moduledoc """
  One line to ride — a member of a segment's `bus`.

  `name` is Amap's own label for the line, usually 线路名(起点站--终点站) such as
  `445路(南十里居--地铁望京西站)`, and `type` the kind of vehicle — 地铁线路 (a subway
  line) is the value worth matching on, since a subway leg is the one that carries
  an `entrance`/`exit` beside it.

  `polyline` is the line's shape, as a flat list of `{lon, lat}` tuples, the same
  shape a step's polyline takes.

  The four times stay strings in Amap's notation, which is not ISO: `"0600"` is
  06:00 and `"2300"` is 23:00. `start_time`/`end_time` are the line's first and last
  departure, `station_start_time`/`station_end_time` this stop's own. `via_num` is
  how many stops the line passes and `via_stops` which ones, as
  `Amap.Direction.Transit.Stop` structs.
  """

  alias Amap.Direction.Transit.Stop

  defstruct [
    :departure_stop,
    :arrival_stop,
    :name,
    :id,
    :type,
    :distance,
    :duration,
    :polyline,
    :start_time,
    :end_time,
    :station_start_time,
    :station_end_time,
    :via_num,
    via_stops: []
  ]

  @type t :: %__MODULE__{
          departure_stop: Stop.t() | nil,
          arrival_stop: Stop.t() | nil,
          name: String.t() | nil,
          id: String.t() | nil,
          type: String.t() | nil,
          distance: String.t() | nil,
          duration: String.t() | nil,
          polyline: [{float(), float()}] | nil,
          start_time: String.t() | nil,
          end_time: String.t() | nil,
          station_start_time: String.t() | nil,
          station_end_time: String.t() | nil,
          via_num: String.t() | nil,
          via_stops: [Stop.t()]
        }
end
