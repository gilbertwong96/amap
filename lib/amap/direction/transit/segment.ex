defmodule Amap.Direction.Transit.Segment do
  @moduledoc """
  One leg of a plan — a member of its `segments`, in travel order.

  A leg is one of four things, and only the fields that apply are filled:

  - `walking` — the walk this leg starts with, as an `Amap.Direction.Path`, because
    a walking answer has the same `distance`/`duration`/`steps` shape a route's path
    does. **That leg's own `origin` and `destination` are not carried**: a `Path` is
    the same struct a route's paths use and has no fields for them, and Amap sends
    them on this leg only.
  - `bus` — the bus or subway lines to ride, as `Amap.Direction.Transit.Busline`
    structs. **An empty list means the leg is not by bus.** Amap nests the same list
    one level deeper (`bus.buslines`); this module carries the list itself, because
    the wrapper holds nothing else.
  - `entrance` and `exit` — the subway entrance and exit to use. **Only an
    underground leg has them**, so they are `nil` everywhere else.
  - `railway` — the train, when the leg is a train.
  """

  alias Amap.Direction.Path
  alias Amap.Direction.Transit.Busline
  alias Amap.Direction.Transit.Railway
  alias Amap.Direction.Transit.Stop

  defstruct [:walking, :entrance, :exit, :railway, bus: []]

  @type t :: %__MODULE__{
          walking: Path.t() | nil,
          bus: [Busline.t()],
          entrance: Stop.t() | nil,
          exit: Stop.t() | nil,
          railway: Railway.t() | nil
        }
end
