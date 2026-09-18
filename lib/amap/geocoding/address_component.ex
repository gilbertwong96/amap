defmodule Amap.Geocoding.AddressComponent do
  @moduledoc """
  The administrative parts of a reverse-geocoded point.

  `city` is **empty for the four municipalities** (北京/上海/天津/重庆 — Beijing, Shanghai,
  Tianjin, Chongqing) and for province-administered counties, where the name appears one
  level up in
  `province`. `neighborhood`, `building` and `street_number` are present only when
  Amap knows them, and `sea_area` only when the point belongs to one.
  """

  alias Amap.Geocoding.Building
  alias Amap.Geocoding.BusinessArea
  alias Amap.Geocoding.Neighborhood
  alias Amap.Geocoding.StreetNumber

  defstruct [
    :country,
    :province,
    :city,
    :citycode,
    :district,
    :adcode,
    :township,
    :towncode,
    :neighborhood,
    :building,
    :street_number,
    :sea_area,
    business_areas: []
  ]

  @type t :: %__MODULE__{
          country: String.t() | nil,
          province: String.t() | nil,
          city: String.t() | nil,
          citycode: String.t() | nil,
          district: String.t() | nil,
          adcode: String.t() | nil,
          township: String.t() | nil,
          towncode: String.t() | nil,
          neighborhood: Neighborhood.t() | nil,
          building: Building.t() | nil,
          street_number: StreetNumber.t() | nil,
          sea_area: String.t() | nil,
          business_areas: [BusinessArea.t()]
        }
end
