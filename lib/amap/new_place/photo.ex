defmodule Amap.NewPlace.Photo do
  @moduledoc """
  One photo of a v5 poi, from the `photos` group.
  """

  defstruct [:title, :url]

  @type t :: %__MODULE__{title: String.t() | nil, url: String.t() | nil}
end
