defmodule Amap.Falcon.Grasproad.Degraded do
  @moduledoc """
  Which parameters Amap had to drop to answer a query.

  `threshold` is the field Amap documents: `true` means the accuracy filter was
  **not** applied, so points the caller asked to exclude are present in the
  result. Amap's wire form is `0` for "still in effect" and `1` for "dropped",
  which is inverted, so this struct carries the meaning rather than the number.
  """

  defstruct threshold: nil

  @type t :: %__MODULE__{threshold: boolean() | nil}
end
