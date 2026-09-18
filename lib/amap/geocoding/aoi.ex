defmodule Amap.Geocoding.Aoi do
  @moduledoc """
  An area of interest containing or near the coordinate.

  `area` is in square metres and `distance` says whether the point is inside the
  area at all: `"0"` means it is, any other value is how far outside it is.
  """

  defstruct [:id, :name, :adcode, :location, :area, :distance, :type]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          adcode: String.t() | nil,
          location: {float(), float()} | nil,
          area: String.t() | nil,
          distance: String.t() | nil,
          type: String.t() | nil
        }
end
