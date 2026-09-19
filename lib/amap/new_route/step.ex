defmodule Amap.NewRoute.Step do
  @moduledoc """
  One section of a path — a member of the `steps` inside `Amap.NewRoute.Path`.

  The base fields are the instruction and what it points at: `orientation` is the
  direction of travel, and **these are the v5 names, not v3's** — `road_name` where v3
  says `road`, `step_distance` where v3 says `distance`. `polyline` decodes Amap's
  `;`-separated string into `{lon, lat}` tuples, so no caller has to split one.

  The groups `show_fields` turns on live here too, because the wire sends them on the
  step rather than on the path: `cost`, `tmcs`, `navi` and `polyline`. **`walk_type`
  is a member of `Amap.NewRoute.Navi`, not a field of this struct** — the page prints
  it as a group of its own, and the wire disagrees; `Amap.NewRoute.Navi` says so.

  A group reaches this struct when the payload carries it on a step —
  `Amap.NewRoute.Path` says which wrappings each group is read in, and only `tmcs` is
  read in more than one.
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
