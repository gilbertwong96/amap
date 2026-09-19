defmodule Amap.Direction.Transit.Stop do
  @moduledoc """
  A station, or a way in — a bus line's stops, a segment's entrance and exit, and a
  train's stops.

  Three shapes share it, and they differ in what they carry. A bus stop and a train
  stop both have `name`, `id` and `location`; **an entrance or an exit has only `name`
  and `location`**, because there is no id to give. `location` is the `{lon, lat}`
  tuple either way, and those are the fields a caller can read without asking which
  kind it holds.

  The rest belong to trains and stay `nil` on a bus stop: `adcode`, the station's
  district code; `time`, the departure time at it in Amap's notation (`"0800"` for
  08:00); `start` and `end`, its 是否始发站/是否终点站 answers (`"1"` or `"0"`); and
  `wait`, the minutes a train waits there. One struct carries all of them because the
  three shared fields are the common case and the union is what Amap sends.
  """

  defstruct [:name, :id, :location, :adcode, :time, :start, :end, :wait]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          id: String.t() | nil,
          location: {float(), float()} | nil,
          adcode: String.t() | nil,
          time: String.t() | nil,
          start: String.t() | nil,
          end: String.t() | nil,
          wait: String.t() | nil
        }
end
