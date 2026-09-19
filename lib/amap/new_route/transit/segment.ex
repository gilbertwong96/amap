defmodule Amap.NewRoute.Transit.Segment do
  @moduledoc """
  One leg of a plan — a member of its `segments`, in travel order.

  This page documents `walking`, `bus` and `railway` as **参考 v3 老接口**, so those
  three keep the v3 structs (`Amap.Direction.Path`, `Amap.Direction.Transit.Busline` and
  `.Railway`, with `.Stop` beneath them) rather than copies of them: the parts v5 inherits
  are v3's, and a second struct for the same shape would drift.

  `taxi` is this page's own addition — the alternative of hailing a car, as
  `Amap.NewRoute.Transit.Taxi`.

  There is no `entrance` or `exit` here: this page's segment does not carry them, though
  v3's does.

  When the call asked for `cost`, this leg carries the `transit_fee` that appears only at
  this level.
  """

  alias Amap.Direction.Path
  alias Amap.Direction.Transit.Busline
  alias Amap.Direction.Transit.Railway
  alias Amap.NewRoute.Transit.Cost
  alias Amap.NewRoute.Transit.Taxi

  defstruct [:walking, :railway, :taxi, :cost, bus: []]

  @type t :: %__MODULE__{
          walking: Path.t() | nil,
          bus: [Busline.t()],
          railway: Railway.t() | nil,
          taxi: Taxi.t() | nil,
          cost: Cost.t() | nil
        }
end
