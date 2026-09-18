defmodule Amap.Geocoding.Geo do
  @moduledoc """
  One match for a geocoded address.

  `level` is how specific the match is — 国家, 省, 市, 区县, 乡镇, 村庄, 热点商圈, 道路,
  道路交叉路口, 兴趣点, 门牌号, 单元号, 公交地铁站点, 门址, 住宅区 or 未知 — and the
  fields above it are filled in only as far as the match goes: a 区县 match has no
  `street`.

  `location` is a `{lon, lat}` tuple; the four municipalities report themselves as
  the `province` **and** the `city`.
  """

  defstruct [
    :country,
    :province,
    :city,
    :citycode,
    :district,
    :street,
    :number,
    :adcode,
    :location,
    :level
  ]

  @type t :: %__MODULE__{
          country: String.t() | nil,
          province: String.t() | nil,
          city: String.t() | nil,
          citycode: String.t() | nil,
          district: String.t() | nil,
          street: String.t() | nil,
          number: String.t() | nil,
          adcode: String.t() | nil,
          location: {float(), float()} | nil,
          level: String.t() | nil
        }
end
