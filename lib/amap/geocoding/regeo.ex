defmodule Amap.Geocoding.Regeo do
  @moduledoc """
  What a reverse-geocoded coordinate is.

  `address_component` describes the point itself; `roads`, `roadinters`, `pois`
  and `aois` describe what is around it, and are only filled in when the call
  asked for `extensions: :all` — they are `[]` otherwise, not `nil`.
  """

  alias Amap.Geocoding.AddressComponent
  alias Amap.Geocoding.Aoi
  alias Amap.Geocoding.Poi
  alias Amap.Geocoding.Road
  alias Amap.Geocoding.RoadInter

  defstruct address_component: nil, roads: [], roadinters: [], pois: [], aois: []

  @type t :: %__MODULE__{
          address_component: AddressComponent.t() | nil,
          roads: [Road.t()],
          roadinters: [RoadInter.t()],
          pois: [Poi.t()],
          aois: [Aoi.t()]
        }
end
