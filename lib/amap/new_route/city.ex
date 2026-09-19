defmodule Amap.NewRoute.City do
  @moduledoc """
  A city a path passes through — the `cities` group, which arrives only when
  `show_fields` asked for it.

  **This is not `Amap.Direction.City`.** v5 says `city` where v3 says `name`, and this
  one holds no districts: v3's answer nests them, v5's does not.
  """

  defstruct [:adcode, :citycode, :city]

  @type t :: %__MODULE__{
          adcode: String.t() | nil,
          citycode: String.t() | nil,
          city: String.t() | nil
        }
end
