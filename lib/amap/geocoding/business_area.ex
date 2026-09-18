defmodule Amap.Geocoding.BusinessArea do
  @moduledoc """
  A shopping or business district the point belongs to.

  `id` is the `adcode` of the district the area sits in, not an identifier of the
  area itself.
  """

  defstruct [:location, :name, :id]

  @type t :: %__MODULE__{
          location: {float(), float()} | nil,
          name: String.t() | nil,
          id: String.t() | nil
        }
end
