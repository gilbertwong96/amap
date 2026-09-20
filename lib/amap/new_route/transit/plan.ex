defmodule Amap.NewRoute.Transit.Plan do
  @moduledoc """
  One way to make the trip — a member of a route's `transits`.

  `distance` is how far this plan goes and `nightflag` whether it depends on a 夜班车
  (`"1"` when it does); both stay the wire's strings, and no unit is recorded for
  either.

  `segments` are the legs in travel order; see `Amap.NewRoute.Transit.Segment`.

  **`Amap.Direction.Transit.Plan` is not this.** The v3 plan answers with `cost`,
  `duration` and `walking_distance` beside its segments, and this page answers with
  `distance` and `nightflag` instead — the same question, two shapes.
  """

  alias Amap.NewRoute.Transit.Segment

  defstruct [:distance, :nightflag, segments: []]

  @type t :: %__MODULE__{
          distance: String.t() | nil,
          nightflag: String.t() | nil,
          segments: [Segment.t()]
        }
end
