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
  asked for stays `nil` — `tmcs` is the exception, and the next paragraph says why.

  **For `tmcs` that `[]` is ambiguous, and deliberately so.** An empty list is what an
  unasked-for group gets and also what an asked-for group with nothing to report gets,
  so a caller reading `tmcs` cannot tell the two apart — a list has nowhere to record
  which it is. The scalar groups do not have this problem: an unasked-for `cost`, `navi`,
  `cities`, `district` or `polyline` is `nil`, and that means the group was not sent at
  this level rather than that Amap had nothing to send — the item-12 run asked for all
  six and the path still read `navi=nil` and `polyline=nil`.

  **`Amap.Direction.Path` is not this.** The v5 page renames a step's `road` and
  `distance`, and its traffic objects carry `tmc_`-prefixed names, so the two versions
  keep separate structs.

  The page prints its groups as objects without saying which level they hang from.
  **The live run settled it: they hang on the step.** A driving payload asked for them
  all carried `cost` on the path and `cost`, `tmcs`, `navi`, `cities` and `polyline` on
  every step, so each group's data is read from wherever it arrives.
  **`tmcs` is the only group read in more than one wrapping at one level**: an object, a
  one-element list of `tmc` objects, or `{"tmc": …}` — the group whose own rules leave the
  level open, read the way `Amap.Direction` reads the `results`/`result` pair on
  `/v3/distance`. `cost` and `navi` are read **as an object or `nil`** for the path, so
  either sent as anything but an object raises rather than mapping; `cities` and `district`
  are read there as an object too, but their mappers stay total, so one of them sent in
  another shape answers `nil` — dropped rather than raised. The live
  run put `cities` on a step though the call asked for it, so `Amap.NewRoute.Step`
  carries that group too, as the list of city objects the third run printed; `district`
  arrived at neither level in that run, so it stays where its page puts it.
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
