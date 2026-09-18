defmodule Amap.Falcon.Position do
  @moduledoc """
  A position, as the track service reports one.

  `/v1/track/terminal/lastpoint` answers with this object and so does every point
  inside a corrected track, so both describe it with this struct rather than one
  each.

  `location` is a `{lon, lat}` tuple, parsed from Amap's `"lon,lat"` string.
  Every other field may be `nil` — correction drops the attributes it cannot
  derive from a snapped track — and may also carry values nobody sent: a
  road-snapped last position reported `speed` 255 and `direction` 511 for points
  that had only a location and a time.
  """

  alias Amap.Numeric

  defstruct [:location, :locatetime, :accuracy, :direction, :speed, :height, :props]

  @type t :: %__MODULE__{
          location: {float(), float()} | nil,
          locatetime: integer() | nil,
          accuracy: number() | nil,
          direction: number() | nil,
          speed: number() | nil,
          height: number() | nil,
          props: map() | nil
        }

  @doc """
  Maps the position object out of a payload.

  One mapper for both endpoints, because one object arrives at both. Field by
  field rather than through `struct/2`, so a field Amap adds later cannot change
  what this module knows.
  """
  @spec from_payload(map()) :: t()
  def from_payload(payload) do
    %__MODULE__{
      location: Amap.Coord.parse_location(payload["location"]),
      locatetime: Numeric.to_integer(payload["locatetime"]),
      accuracy: payload["accuracy"],
      direction: payload["direction"],
      speed: payload["speed"],
      height: payload["height"],
      props: payload["props"]
    }
  end
end
