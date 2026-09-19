defmodule Amap.Direction.Transit do
  @moduledoc """
  公交换乘 — the plans Amap offers for one trip by public transport.

  Amap's own name for this page is 公交路径规划, and "公共交通" is meant literally: a
  plan can combine walking, buses, the subway and trains. Every answer is a list of
  换乘 (changes) rather than a single vehicle, which is why this struct holds
  `transits` — one entry per way to make the trip, Amap's own preference first —
  and why each of those is a plan of several segments.

  `distance` is how far the trip is (metres) and `taxi_cost` what a taxi would cost
  instead (yuan); both stay strings, as Amap writes them. `origin` and `destination`
  are the `{lon, lat}` tuples the call asked for.

  An answer with no `route` in it is not an error — `transits` is simply empty, the
  same way `Amap.Direction.walking/4` answers an empty route.
  """

  alias Amap.Direction.Transit.Plan

  defstruct [:origin, :destination, :distance, :taxi_cost, transits: []]

  @type t :: %__MODULE__{
          origin: {float(), float()} | nil,
          destination: {float(), float()} | nil,
          distance: String.t() | nil,
          taxi_cost: String.t() | nil,
          transits: [Plan.t()]
        }
end
