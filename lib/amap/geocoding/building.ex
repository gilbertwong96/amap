defmodule Amap.Geocoding.Building do
  @moduledoc """
  The building a point is in, when Amap knows which one.
  """

  defstruct [:name, :type]

  @type t :: %__MODULE__{name: String.t() | nil, type: String.t() | nil}
end
