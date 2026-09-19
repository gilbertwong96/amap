defmodule Amap.NewRoute.Transit do
  @moduledoc """
  公交路径规划 2.0 — the plans Amap offers for one trip by public transport.

  Amap's own name for this page is 公交路线规划, and "公共交通" is meant literally: a plan
  can combine walking, buses, the subway, trains and a taxi. Every answer is a list of
  换乘 (changes) — `transits`, one entry per way to make the trip, Amap's own preference
  first — rather than a single vehicle.

  The shape is v3's with three differences, because the two pages really do answer
  differently: a plan carries its own `distance` and `nightflag` where v3's carried
  `cost` and `walking_distance`; there is no route-level `taxi_cost`; and a segment can
  hold a `taxi` option (`Amap.NewRoute.Transit.Taxi`) that v3 has no equivalent of.

  Amap leaves `route` out entirely when it found no plan, which is an answer rather than
  a failure: `transits` is then `[]`, the way `Amap.NewRoute.walking/4` answers an empty
  route.

  When the call asked for the `cost` group, this struct carries the block that appears
  **only at this level** — `taxi_fee` — while each segment carries the `transit_fee` that
  appears only there. The page's own caveat: `steps` never carry a cost at all.
  """

  alias Amap.NewRoute.Transit.Cost
  alias Amap.NewRoute.Transit.Plan

  defstruct [:origin, :destination, :cost, transits: []]

  @type t :: %__MODULE__{
          origin: {float(), float()} | nil,
          destination: {float(), float()} | nil,
          cost: Cost.t() | nil,
          transits: [Plan.t()]
        }
end
