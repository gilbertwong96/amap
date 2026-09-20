defmodule Amap.Place.IndoorData do
  @moduledoc """
  A v3 POI's 室内地图相关数据 (`indoor_data`).

  The page puts `cpid`, `floor` and `truefloor` under this object, and sends it only with
  `extensions=all`; when `indoor_map` is `"0"` the object is empty, so its fields are
  `nil` and `indoor_map` is the field that says whether there is indoor data at all.
  """

  defstruct [:cpid, :floor, :truefloor]

  @type t :: %__MODULE__{
          cpid: String.t() | nil,
          floor: String.t() | nil,
          truefloor: String.t() | nil
        }
end
