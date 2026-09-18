defmodule Amap.Geocoding.RoadInter do
  @moduledoc """
  A road intersection near the point, named by the two roads that meet there.
  """

  defstruct [
    :distance,
    :direction,
    :location,
    :first_id,
    :first_name,
    :second_id,
    :second_name
  ]

  @type t :: %__MODULE__{
          distance: String.t() | nil,
          direction: String.t() | nil,
          location: {float(), float()} | nil,
          first_id: String.t() | nil,
          first_name: String.t() | nil,
          second_id: String.t() | nil,
          second_name: String.t() | nil
        }
end
