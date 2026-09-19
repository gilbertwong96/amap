defmodule Amap.NewRoute.Path do
  @moduledoc """
  One way Amap can take you — a member of the `paths` inside `Amap.NewRoute.Route`.

  The base fields are `distance` and `restriction`, plus `steps`: the turn-by-turn
  breakdown. `restriction` is Amap's 限行 answer — `"0"` when a limiting rule was
  avoided or did not apply, `"1"` when one could not be — and stays the string the wire
  sends rather than becoming a boolean the page never promised.

  Everything else arrives only when the call asked for it with `show_fields`, and each
  field says which group it came from: `cost` (what the plan takes and charges), `tmcs`
  (the traffic flow), `navi` (the driving actions), `cities` and `district` (what the
  path crosses) and `polyline`, decoded into `{lon, lat}` tuples. A group that was not
  asked for stays `nil`, or `[]` where the field holds a collection.

  **For `tmcs` that `[]` is ambiguous, and deliberately so.** An empty list is what an
  unasked-for group gets and also what an asked-for group with nothing to report gets,
  so a caller reading `tmcs` cannot tell the two apart — a list has nowhere to record
  which it is. The scalar groups do not have this problem: an unasked-for `cost`, `navi`,
  `cities`, `district` or `polyline` is `nil`, which no answer produces.

  **`Amap.Direction.Path` is not this.** The v5 page renames a step's `road` and
  `distance`, and its traffic objects carry `tmc_`-prefixed names, so the two versions
  keep separate structs.

  The page prints its groups as objects without saying which level they hang from.
  **`tmcs` is the only group read in more than one wrapping**: an object, a one-element
  list of `tmc` objects, or `{"tmc": …}` — the group whose own rules leave the level
  open, read the way `Amap.Direction` reads the `results`/`result` pair on `/v3/distance`.
  `cost`, `navi`, `cities` and `district` are read **as an object or `nil`**, so one of
  them sent wrapped raises rather than mapping, and `Amap.NewRoute.Step` has no
  `cities`/`district` field at all, so a step carrying either drops it. Task 11's live
  run records the shape that really arrives.
  """

  alias Amap.NewRoute.City
  alias Amap.NewRoute.Cost
  alias Amap.NewRoute.District
  alias Amap.NewRoute.Navi
  alias Amap.NewRoute.Step
  alias Amap.NewRoute.Tmc

  defstruct [
    :distance,
    :restriction,
    :cost,
    :navi,
    :cities,
    :district,
    :polyline,
    steps: [],
    tmcs: []
  ]

  @type t :: %__MODULE__{
          distance: String.t() | nil,
          restriction: String.t() | nil,
          cost: Cost.t() | nil,
          navi: Navi.t() | nil,
          cities: City.t() | nil,
          district: District.t() | nil,
          polyline: [{float(), float()}] | nil,
          steps: [Step.t()],
          tmcs: [Tmc.t()]
        }
end
