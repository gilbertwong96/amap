defmodule Amap.Grasproad.Point do
  @moduledoc """
  One corrected coordinate, as `points[]` carries it.

  The page splits the pair into `x` 经度 and `y` 纬度 — its 维度 is a typo — and types
  neither. The live run returns both as JSON **floats** (`116.47893348907736`), the
  `/v4/`-on-`restapi` generation's numeric shape, while the older Web-service pages send
  strings; each is kept as sent rather than converted.
  """

  defstruct [:x, :y]

  @type t :: %__MODULE__{
          x: String.t() | number() | nil,
          y: String.t() | number() | nil
        }
end
