defmodule Amap.Direction.Transit.Segment do
  @moduledoc """
  One leg of a plan — a member of its `segments`, in travel order.

  A leg is one of four things, and only the fields that apply are filled:

  - `walking` — the walk this leg makes, as an `Amap.Direction.Transit.Walking`. It
    carries its own `origin`/`destination` as well as `distance`/`duration`/`steps`,
    because it is a walk between two points on the plan rather than between the
    route's ends.
  - `bus` — the bus or subway lines to ride, as `Amap.Direction.Transit.Busline`
    structs. **An empty list means the leg is not by bus.** Amap nests the same list
    one level deeper (`bus.buslines`); this module carries the list itself, because
    the wrapper holds nothing else.
  - `entrance` and `exit` — the subway entrance and exit to use. **Only an
    underground leg has them**, so they are `nil` everywhere else.
  - `railway` — the train, when the leg is a train.
  """

  alias Amap.Direction.Transit.Busline
  alias Amap.Direction.Transit.Railway
  alias Amap.Direction.Transit.Stop
  alias Amap.Direction.Transit.Walking

  defstruct [:walking, :entrance, :exit, :railway, bus: []]

  @type t :: %__MODULE__{
          walking: Walking.t() | nil,
          bus: [Busline.t()],
          entrance: Stop.t() | nil,
          exit: Stop.t() | nil,
          railway: Railway.t() | nil
        }
end
