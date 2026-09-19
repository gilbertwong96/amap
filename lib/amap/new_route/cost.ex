defmodule Amap.NewRoute.Cost do
  @moduledoc """
  What a path costs — the `cost` group, which arrives only when `show_fields` asked
  for it.

  `duration` is the time the whole plan takes including the sections', `tolls` what its
  toll roads charge and `toll_distance` how long those stretches are.

  **The amounts keep the wire's form**: they are strings, and a value Amap did not send
  stays `nil` rather than becoming a zero.
  """

  defstruct [:duration, :tolls, :toll_distance]

  @type t :: %__MODULE__{
          duration: String.t() | nil,
          tolls: String.t() | nil,
          toll_distance: String.t() | nil
        }
end
