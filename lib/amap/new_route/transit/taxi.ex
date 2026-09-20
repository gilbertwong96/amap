defmodule Amap.NewRoute.Transit.Taxi do
  @moduledoc """
  Hailing a car instead — a segment's `taxi`.

  This is v5's own field: the v3 transit page has no equivalent, and the two pages' plans
  differ for the same reason.

  `price` is the estimated fare, `drivetime` how long the ride would take and
  `distance` how far it goes; all three stay the wire's strings, and the page states no
  unit for any of them. `polyline` is the ride's
  coordinates, decoded into `{lon, lat}` tuples.

  `startpoint`/`startname` and `endpoint`/`endname` are where the car collects and drops
  off — the coordinates and the names Amap gives them.
  """

  defstruct [
    :price,
    :drivetime,
    :distance,
    :polyline,
    :startpoint,
    :startname,
    :endpoint,
    :endname
  ]

  @type t :: %__MODULE__{
          price: String.t() | nil,
          drivetime: String.t() | nil,
          distance: String.t() | nil,
          polyline: [{float(), float()}] | nil,
          startpoint: String.t() | nil,
          startname: String.t() | nil,
          endpoint: String.t() | nil,
          endname: String.t() | nil
        }
end
