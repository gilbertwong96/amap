defmodule Amap.Grasproad.Point do
  @moduledoc """
  One corrected coordinate, as `points[]` carries it.

  The page splits the pair into `x` 经度 and `y` 纬度 — its 维度 is a typo — and types
  neither. The v4 generation sends them as JSON numbers while the older Web-service
  pages send strings, so each is kept as sent rather than converted; the batch's live
  check prints which shape this endpoint really uses.
  """

  defstruct [:x, :y]

  @type t :: %__MODULE__{
          x: String.t() | number() | nil,
          y: String.t() | number() | nil
        }
end
