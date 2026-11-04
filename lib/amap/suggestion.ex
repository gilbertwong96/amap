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
  something — is `nil`, and `from_map/1` answers that.
  """

  defstruct keywords: [], cities: []

  @type t :: %__MODULE__{keywords: [String.t()], cities: [String.t()]}

  @doc """
  Reads a `suggestion` object, or `nil` when Amap sent none.

  Total on purpose: an answer that matched something omits the object, and the two
  services should not each keep their own clause for that absence. A value that is not
  an object is answered the same way, the way `Amap.Routing`'s mappers treat the shapes
  Amap leaves open.
  """
  @spec from_map(Amap.JSON.value()) :: t() | nil
  def from_map(payload) when is_map(payload) do
    %__MODULE__{keywords: payload["keywords"] || [], cities: payload["cities"] || []}
  end

  def from_map(_other), do: nil
end
