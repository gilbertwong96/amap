defmodule Amap.Direction.Transit.Plan do
  @moduledoc """
  One way to make the trip — a member of a route's `transits`.

  `cost` is what it costs, `duration` how long it takes and `walking_distance` how
  much of that is on foot — the number a caller compares plans by when the question is
  走不走得动 rather than 快不快. All three stay the wire's strings, and no unit is
  recorded for any of them.

  `nightflag` is Amap's answer rather than a request: `"1"` when this plan depends
  on a 夜班车 (a night bus). It stays the wire's string.

  `segments` are the legs in travel order; see `Amap.Direction.Transit.Segment`.

  Amap also sends `emergency` — the events that affect this plan, such as 甩站
  (skipped stops), 突发 (incidents) and 停运 (suspended service) — but **only when the
  call asked for `extensions: :all`, and this module does not map it**: the page does
  not say whether one plan carries a single event or a list of them, and a guessed
  shape would be worse than an absent field.
  """

  alias Amap.Direction.Transit.Segment

  defstruct [:cost, :duration, :nightflag, :walking_distance, segments: []]

  @type t :: %__MODULE__{
          cost: String.t() | nil,
          duration: String.t() | nil,
          nightflag: String.t() | nil,
          walking_distance: String.t() | nil,
          segments: [Segment.t()]
        }
end
