defmodule Amap.Direction.Step do
  @moduledoc """
  One leg of a path — a member of its `steps`.

  `instruction` is Amap's own sentence for the leg (沿当前道路向前步行100米 — walk 100 m
  straight ahead), and `action`/`assistant_action` are its shorter labels: 直行
  (straight on), 左转 (left), 靠右 (bear right), 通过人行横道 (cross at the crossing) and
  so on. **They arrive in Chinese and stay there**, so an application that displays
  them needs no lookup and one that reasons about them matches on `action`.

  `walk_type` says what the leg crosses, as Amap's own code and with gaps in the
  range: `"0"` an ordinary road, `"1"` a pedestrian crossing, `"3"` an underpass,
  `"4"` an overpass, `"5"` a subway passage, `"30"` a ferry. It stays a string.

  `polyline` is the leg's points as one flat list of `{lon, lat}` tuples — Amap
  writes them as a single `;`-separated string, and a leg has no parts. (The `|`
  that splits a boundary into parts belongs to 行政区划, not to a route.)

  `tolls`, `toll_distance` and `toll_road` are driving's and stay `nil` elsewhere,
  as does `tmcs` — the traffic flow along this leg, which driving sends with
  `extensions: :all` only.
  """

  alias Amap.Direction.Tmc

  defstruct [
    :instruction,
    :road,
    :distance,
    :orientation,
    :duration,
    :polyline,
    :action,
    :assistant_action,
    :walk_type,
    :tolls,
    :toll_distance,
    :toll_road,
    tmcs: []
  ]

  @type t :: %__MODULE__{
          instruction: String.t() | nil,
          road: String.t() | nil,
          distance: String.t() | nil,
          orientation: String.t() | nil,
          duration: String.t() | nil,
          polyline: [{float(), float()}] | nil,
          action: String.t() | nil,
          assistant_action: String.t() | nil,
          walk_type: String.t() | nil,
          tolls: String.t() | nil,
          toll_distance: String.t() | nil,
          toll_road: String.t() | nil,
          tmcs: [Tmc.t()]
        }
end
