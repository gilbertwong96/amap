defmodule Amap.NewRoute.Step do
  @moduledoc """
  One section of a path — a member of the `steps` inside `Amap.NewRoute.Path`.

  The base fields are the instruction and what it points at: `orientation` is the
  direction of travel, and **these are the v5 names, not v3's** — `road_name` where v3
  says `road`, `step_distance` where v3 says `distance`. `polyline` decodes Amap's
  `;`-separated string into `{lon, lat}` tuples, so no caller has to split one.

  The groups `show_fields` turns on reach this struct when the wire puts them on a step,
  and the live run showed it puts nearly all of them there: the step carried `cost`,
  `tmcs`, `navi`, `cities` and `polyline`, while the path carried `cost` alone.
  **`walk_type` is a member of `Amap.NewRoute.Navi`, not a field of this struct** — the
  page prints it as a group of its own, and the wire disagrees; `Amap.NewRoute.Navi`
  says so.

  `cities` is the one group whose home and shape disagree across the sources: the page
  lists it with the path's groups, the live run's step keys carried it while the path
  carried `cost` alone, and no run has printed what it holds. So this field reads the
  object `Amap.NewRoute.City` documents, or a list of them the way v3 wraps the same
  group, and stays `nil` for any other shape — item 12's live helper prints the raw
  value, and the next run narrows this to one of the two.
  """

  alias Amap.NewRoute.City
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
    :cities,
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
          cities: City.t() | [City.t()] | nil,
          polyline: [{float(), float()}] | nil,
          tmcs: [Tmc.t()]
        }
end
