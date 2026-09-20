defmodule Amap.NewRoute.City do
  @moduledoc """
  A city a path passes through — the `cities` group, which arrives only when
  `show_fields` asked for it.

  **This is not `Amap.Direction.City`.** v5 says `city` where v3 says `name`; the
  nesting is otherwise the same, and `districts` are the districts of that city the
  route crosses, the way v3's answer carries them.
  """

  alias Amap.NewRoute.District

  defstruct [:adcode, :citycode, :city, districts: []]

  @type t :: %__MODULE__{
          adcode: String.t() | nil,
          citycode: String.t() | nil,
          city: String.t() | nil,
          districts: [District.t()]
        }
end
