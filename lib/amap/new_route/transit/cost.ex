defmodule Amap.NewRoute.Transit.Cost do
  @moduledoc """
  What a transit plan costs — the `cost` group, which arrives only when `show_fields`
  asked for it.

  Transit's `cost` group is the one that **splits across two levels**: `taxi_fee`
  appears only on the route (`Amap.NewRoute.Transit`), `transit_fee` only under a
  segment (`Amap.NewRoute.Transit.Segment`), and the page says plainly that a step never
  carries a cost at all. One struct holds both, and each level fills only what it has, so
  a caller reading `taxi_fee` off a segment gets `nil` rather than a surprise.

  `duration` is the time the trip takes (seconds).

  **The amounts keep the wire's form**: they are strings, and a value Amap did not send
  stays `nil` rather than becoming a zero.
  """

  defstruct [:duration, :taxi_fee, :transit_fee]

  @type t :: %__MODULE__{
          duration: String.t() | nil,
          taxi_fee: String.t() | nil,
          transit_fee: String.t() | nil
        }
end
