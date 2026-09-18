defmodule Amap.Falcon.TerminalSearch.Location do
  @moduledoc """
  A terminal's last reported position, as the search endpoints return it.

  Search results carry the position as an object; `Amap.Falcon.TerminalMonitor`
  gets the same information as a bare `"lon,lat"` string from a different
  endpoint, which is why the two shapes live in different modules.
  """

  defstruct [:latitude, :longitude, :speed, :direction, :height, :accuracy]

  @type t :: %__MODULE__{
          latitude: number() | nil,
          longitude: number() | nil,
          speed: number() | nil,
          direction: number() | nil,
          height: number() | nil,
          accuracy: number() | nil
        }
end
