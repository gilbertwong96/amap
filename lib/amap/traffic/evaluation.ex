defmodule Amap.Traffic.Evaluation do
  @moduledoc """
  How much of the queried area is moving how well.

  The four fields are percentages and stay strings, which is what Amap sends:
  `expedite` 畅通 (flowing), `congested` 缓行 (slowed), `blocked` 拥堵 (congested) and
  `unknown` for stretches Amap has no reading for.
  """

  defstruct [:expedite, :congested, :blocked, :unknown]

  @type t :: %__MODULE__{
          expedite: String.t() | nil,
          congested: String.t() | nil,
          blocked: String.t() | nil,
          unknown: String.t() | nil
        }
end
