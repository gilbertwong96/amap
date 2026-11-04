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

  @doc """
  Reads one wire photo into this struct, or `nil` when the entry is not an object.

  Both generations' mappers go through this one function: the two keys are the struct's
  own field names, so the module that owns the shape is the one that reads them.
  """
  @spec from_map(Amap.JSON.value()) :: t() | nil
  def from_map(payload) when is_map(payload),
    do: %__MODULE__{title: payload["title"], url: payload["url"]}

  def from_map(_other), do: nil
end
