defmodule Amap.Place.Photo do
  @moduledoc """
  One photo of a POI, from the `photos` list.

  v3's 搜索POI answers it under `photos` once the call asked for `extensions=all`; v5's
  搜索POI 2.0 answers the same two keys as a `photos` group. The shape is Amap's rather
  than either page's, so `Amap.NewPlace.Poi` holds these too instead of the two
  generations keeping a struct each.
  """

  defstruct [:title, :url]

  @type t :: %__MODULE__{title: String.t() | nil, url: String.t() | nil}
end
