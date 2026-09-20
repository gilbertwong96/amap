defmodule Amap.Place.Result do
  @moduledoc """
  What a v3 搜索POI query answered: the POIs, Amap's count, and its suggestion.

  `count` stays the string Amap sent. The page calls it 搜索方案数目 — the size of the
  result set — but on a generic keyword without a `city` Amap answers a city list
  instead of POIs and counts the cities there; that list is what `suggestion` carries,
  and it is the only field that says what Amap thought was meant.

  `Amap.NewPlace.Result` is the v5 counterpart and has no `suggestion`: the 搜索POI 2.0
  pages do not document one.

  `pois` is never `nil`; a suggestion-only answer reads as an empty list, so a caller
  can always count rows without a nil check.
  """

  alias Amap.Place.Poi
  alias Amap.Place.Suggestion

  defstruct [:count, :suggestion, pois: []]

  @type t :: %__MODULE__{
          count: String.t() | nil,
          suggestion: Suggestion.t() | nil,
          pois: [Poi.t()]
        }
end
