defmodule Amap.Geocoding.Poi do
  @moduledoc """
  A point of interest near the coordinate.

  `type` is Amap's `;`-separated classification, and `businessarea` is the name of
  the business district it belongs to.
  """

  defstruct [
    :id,
    :name,
    :type,
    :tel,
    :distance,
    :direction,
    :address,
    :location,
    :businessarea
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          type: String.t() | nil,
          tel: String.t() | nil,
          distance: String.t() | nil,
          direction: String.t() | nil,
          address: String.t() | nil,
          location: {float(), float()} | nil,
          businessarea: String.t() | nil
        }
end
