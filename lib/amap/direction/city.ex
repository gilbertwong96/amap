defmodule Amap.Direction.City do
  @moduledoc """
  A city a planned route crosses — a member of a path's `cities`.

  Its `districts` are the districts of that city which the route also crosses, so
  the nesting mirrors Amap's own answer rather than a second lookup. `citycode`
  and `adcode` keep the wire's form.
  """

  alias Amap.Direction.District

  defstruct [:name, :citycode, :adcode, districts: []]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          citycode: String.t() | nil,
          adcode: String.t() | nil,
          districts: [District.t()]
        }
end
