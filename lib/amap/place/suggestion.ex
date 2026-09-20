defmodule Amap.Place.Suggestion do
  @moduledoc """
  What Amap suggests when a keyword search matched nothing in the requested scope.

  The page describes it as the 城市建议列表: when the text keyword has no result in the
  limited city — or no `city` at all and the keyword is a generic word like 美食 — the
  answer is a list of cities, each with how many results matched there
  (`Amap.Place.Suggestion.City`), instead of a POI list. `keywords` is Amap's
  keyword suggestion list beside them.

  Both lists are `[]` when Amap sent none, so the struct never needs a nil check; whole
  `suggestion` is `nil` on an answer that carried none at all — which is what
  `Amap.Place.detail/3` answers.
  """

  alias Amap.Place.Suggestion.City

  defstruct keywords: [], cities: []

  @type t :: %__MODULE__{keywords: [String.t()], cities: [City.t()]}
end
