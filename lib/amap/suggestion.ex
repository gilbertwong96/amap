defmodule Amap.Suggestion do
  @moduledoc """
  Amap's `suggestion` object: keywords, and the cities it suggests instead.

  The 公交信息查询 keyword searches (`Amap.Bus`) and the district search
  (`Amap.District`) send the same two lists under the same two names, so one struct
  carries both rather than each service keeping a copy that would drift.

  `Amap.Place.Suggestion` is a different shape and stays its own module: its `cities`
  are objects (`Amap.Place.Suggestion.City`) carrying a result count each, not strings.

  Both lists are `[]` when Amap sent none, so a caller never needs a nil check on
  either. A `suggestion` Amap left out altogether — which is every answer that matched
  something — is `nil`.
  """

  defstruct keywords: [], cities: []

  @type t :: %__MODULE__{keywords: [String.t()], cities: [String.t()]}
end
