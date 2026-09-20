defmodule Amap.NewPlace.Result do
  @moduledoc """
  What a v5 搜索POI 2.0 query answered: the POIs and Amap's count.

  `count` stays the string Amap sent. The 2.0 page defines it as 单次请求返回的实际 poi 点的
  个数 — the POIs this one request returned — where the v3 page calls the same field 搜索方案
  数目; neither number is the total behind the 200-row ceiling.

  The 2.0 pages document no `suggestion` (v3's does, and `Amap.Place.Result` carries it),
  so this struct has none. The integration check prints the raw envelope keys, so the owed
  live run says whether one arrives anyway.

  `Amap.NewPlace.detail/3`'s response table lists no `count` at all, so its answers leave
  `count` `nil`.
  """

  alias Amap.NewPlace.Poi

  defstruct [:count, pois: []]

  @type t :: %__MODULE__{count: String.t() | nil, pois: [Poi.t()]}
end
