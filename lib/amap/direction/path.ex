defmodule Amap.Direction.Path do
  @moduledoc """
  One way Amap can take you — a member of the `paths` inside a route.

  `steps` is the turn-by-turn breakdown, in the order you would walk or drive it.

  The driving-only scalars here stay `nil` on every other answer: `strategy` is the
  routing strategy that produced this path, `tolls` and `toll_distance` what the toll
  roads on it cost, `traffic_lights` how many lights it passes, and `restriction`
  Amap's own 限行 answer — `"0"` when a limiting rule was avoided or did not apply,
  `"1"` when one could not be.

  **They keep the wire's form.** Amounts are strings, `restriction` and
  `traffic_lights` are strings, and nothing is parsed into a number here — a
  payload Amap never sends a value in stays `nil` rather than becoming a zero.
  """

  alias Amap.Direction.Step

  defstruct [
    :distance,
    :duration,
    :strategy,
    :tolls,
    :restriction,
    :traffic_lights,
    :toll_distance,
    steps: []
  ]

  @type t :: %__MODULE__{
          distance: String.t() | nil,
          duration: String.t() | nil,
          strategy: String.t() | nil,
          tolls: String.t() | nil,
          restriction: String.t() | nil,
          traffic_lights: String.t() | nil,
          toll_distance: String.t() | nil,
          steps: [Step.t()]
        }
end
