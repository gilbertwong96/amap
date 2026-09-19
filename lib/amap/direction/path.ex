defmodule Amap.Direction.Path do
  @moduledoc """
  One way Amap can take you — a member of the `paths` inside a route.

  `steps` is the turn-by-turn breakdown, in the order you would walk or drive it.

  The driving-only scalars here stay `nil` on every other answer: `strategy` is the
  routing strategy that produced this path, `tolls` and `toll_distance` what the toll
  roads on it cost, `traffic_lights` how many lights it passes, and `restriction`
  Amap's own 限行 answer — `"0"` when a limiting rule was avoided or did not apply,
  `"1"` when one could not be.

  The driving-only collections are empty elsewhere too. `tmcs` reports the traffic
  flow stretch by stretch and `cities`/`districts` the places the path crosses; Amap
  sends all three for driving, and only with `extensions: :all`.

  **`roads` replaces `steps`, it does not sit above them.** It arrives only when
  driving's `:roadaggregation` option is set, and the page words the flag as 在 `steps`
  上层增加 `roads` 做聚合; the live run saw a path whose keys held `roads` and no `steps`
  at all, so a caller who asks for aggregation reads the route from `roads` and from
  nowhere else. Each entry is carried exactly as the wire sends it — the page states no
  entry shape, and the live run recorded only that there were seven of them.

  **They keep the wire's form.** Amounts are strings, `restriction` and
  `traffic_lights` are strings, and nothing is parsed into a number here — a
  payload Amap never sends a value in stays `nil` rather than becoming a zero.
  """

  alias Amap.Direction.City
  alias Amap.Direction.District
  alias Amap.Direction.Step
  alias Amap.Direction.Tmc

  defstruct [
    :distance,
    :duration,
    :strategy,
    :tolls,
    :restriction,
    :traffic_lights,
    :toll_distance,
    steps: [],
    tmcs: [],
    cities: [],
    districts: [],
    roads: []
  ]

  @typedoc """
  The `roads` grouping `:roadaggregation` produces, entries exactly as the wire sends
  them. The page states no entry shape and the live run recorded only a count, so this
  is deliberately the JSON value rather than a struct of guessed fields.
  """
  @type road :: Amap.JSON.value()

  @type t :: %__MODULE__{
          distance: String.t() | nil,
          duration: String.t() | nil,
          strategy: String.t() | nil,
          tolls: String.t() | nil,
          restriction: String.t() | nil,
          traffic_lights: String.t() | nil,
          toll_distance: String.t() | nil,
          steps: [Step.t()],
          tmcs: [Tmc.t()],
          cities: [City.t()],
          districts: [District.t()],
          roads: [road()]
        }
end
