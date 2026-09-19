defmodule Amap.NewRoute.Step do
  @moduledoc """
  One section of a path — a member of the `steps` inside `Amap.NewRoute.Path`.

  The base fields are the instruction and what it points at: `orientation` is the
  direction of travel, and **these are the v5 names, not v3's** — `road_name` where v3
  says `road`, `step_distance` where v3 says `distance`. `polyline` decodes Amap's
  `;`-separated string into `{lon, lat}` tuples, so no caller has to split one.

  The groups `show_fields` turns on live here too, because the page lists them without
  saying which level they hang from: `cost`, `tmcs`, `navi` (whose `walk_type` carries
  the road-type code) and `polyline`. `Amap.NewRoute.Path` says the same about its own,
  and the mapper fills whichever level Amap answers with.
  """

  alias Amap.NewRoute.Cost
  alias Amap.NewRoute.Navi
  alias Amap.NewRoute.Tmc

  defstruct [
    :instruction,
    :orientation,
    :road_name,
    :step_distance,
    :cost,
    :navi,
    :polyline,
    tmcs: []
  ]

  @type t :: %__MODULE__{
          instruction: String.t() | nil,
          orientation: String.t() | nil,
          road_name: String.t() | nil,
          step_distance: String.t() | nil,
          cost: Cost.t() | nil,
          navi: Navi.t() | nil,
          polyline: [{float(), float()}] | nil,
          tmcs: [Tmc.t()]
        }
end
