defmodule Amap.Geocoding.Neighborhood do
  @moduledoc """
  The residential community or campus a point is in, when Amap knows one.
  """

  defstruct [:name, :type]

  @type t :: %__MODULE__{name: String.t() | nil, type: String.t() | nil}
end
