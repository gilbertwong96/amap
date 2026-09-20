defmodule Amap.Place.Photo do
  @moduledoc """
  One photo of a v3 POI, from the `photos` list `extensions=all` adds.
  """

  defstruct [:title, :url]

  @type t :: %__MODULE__{title: String.t() | nil, url: String.t() | nil}
end
