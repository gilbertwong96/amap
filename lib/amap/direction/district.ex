defmodule Amap.Direction.District do
  @moduledoc """
  A district a planned route crosses — a member of a path's `districts`, and of a
  city's own `districts` inside `cities`.

  `adcode` is Amap's code for the district and keeps the wire's form: 110105 is
  朝阳区, leading zeros and all.
  """

  defstruct [:name, :adcode]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          adcode: String.t() | nil
        }
end
