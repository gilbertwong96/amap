defmodule Amap.NewRoute.District do
  @moduledoc """
  A district a path passes through — the `district` group, which arrives only when
  `show_fields` asked for it.

  A path carries one of these rather than v3's list, which is why this module's struct
  is not `Amap.Direction.District` with a different field on the parent: the two pages
  describe different shapes.
  """

  defstruct [:name, :adcode]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          adcode: String.t() | nil
        }
end
