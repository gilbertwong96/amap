defmodule Amap.NewPlace.Navi do
  @moduledoc """
  A v5 poi's 导航位置相关信息 (`navi`), returned only when `show_fields` asks for it.

  `navi_poiid` is the navigation point's coordinate pair as Amap sends it — a large
  area-shaped POI's entrances, for instance — and the two locations decode into `{lon, lat}`
  tuples like every other coordinate in the SDK.
  """

  defstruct [:navi_poiid, :entr_location, :exit_location, :gridcode]

  @type t :: %__MODULE__{
          navi_poiid: String.t() | nil,
          entr_location: {float(), float()} | nil,
          exit_location: {float(), float()} | nil,
          gridcode: String.t() | nil
        }
end
