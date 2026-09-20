defmodule Amap.NewPlace.Result do
  @moduledoc """
  What a v5 搜索POI 2.0 query answered: the POIs and Amap's count.

  `count` stays the string Amap sent. The 2.0 page defines it as 单次请求返回的实际 poi 点的
  个数 — the POIs this one request returned — where the v3 page calls the same field 搜索方案
  数目; neither number is the total behind the 200-row ceiling.

  The 2.0 pages document no `suggestion` (v3's does, and `Amap.Place.Result` carries it),
  so this struct has none. The live run agrees: the 2.0 text response answers without one
  (its envelope carries `count`/`info`/`infocode`/`pois`/`status` and no `suggestion`), and the
  integration check keeps printing the raw keys so that stays visible rather than owed.

  `Amap.NewPlace.detail/3`'s response table lists no `count`, but the service sends one
  anyway — a two-id call answered `count "2"` — so `count` carries the string as sent.
  """

  alias Amap.NewPlace.Poi

  defstruct [:count, pois: []]

  @type t :: %__MODULE__{count: String.t() | nil, pois: [Poi.t()]}
end
