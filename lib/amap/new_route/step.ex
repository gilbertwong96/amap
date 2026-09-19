defmodule Amap.NewRoute.Step do
  @moduledoc """
  One section of a path — a member of the `steps` inside `Amap.NewRoute.Path`.

  The base fields are the instruction and what it points at: `orientation` is the
  direction of travel, and **these are the v5 names, not v3's** — `road_name` where v3
  says `road`, `step_distance` where v3 says `distance`. `polyline` decodes Amap's
  `;`-separated string into `{lon, lat}` tuples, so no caller has to split one.

  The groups `show_fields` turns on live here too, because the page prints them at a
  level without saying which one: `cost`, `tmcs`, `navi`, `walk_type` and `polyline`.
  **`walk_type` is its own group and a field of this struct**, not a member of `navi`:
  every group is named after the field it controls, and the page prints `walk_type` at
  the same level as `polyline` — a group — while `navi`'s children are only `action` and
  `assistant_action`. It is Amap's road-type code (0 普通道路 … 30 轮渡, gaps included)
  and stays the wire's string, the way the statuses do.

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
    :walk_type,
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
          walk_type: String.t() | nil,
          cost: Cost.t() | nil,
          navi: Navi.t() | nil,
          polyline: [{float(), float()}] | nil,
          tmcs: [Tmc.t()]
        }
end
