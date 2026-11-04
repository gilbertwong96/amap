defmodule Amap.Direction.District do
  @moduledoc """
  A district a route crosses — the wire's `name` and `adcode`.

  v3 carries `districts` as a list, on a path and on each city inside `cities`; v5's
  path carries a single `district` group. That is a difference in how many arrive, not
  in the object, so both generations use this struct: `Amap.Routing.district/1` is the
  one mapper, and `Amap.NewRoute.Path` holds one of these where
  `Amap.Direction.Path` holds a list.

  `adcode` is Amap's code for the district and keeps the wire's form: 110105 is
  朝阳区, leading zeros and all.
  """

  defstruct [:name, :adcode]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          adcode: String.t() | nil
        }
end
