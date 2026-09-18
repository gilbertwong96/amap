defmodule Amap.Geocoding.Geo do
  @moduledoc """
  One match for a geocoded address.

  `level` is how specific the match is, as one of Amap's own labels — 国家 (country),
  省 (province), 市 (city), 区县 (district), 乡镇 (town), 村庄 (village), 热点商圈 (business
  district), 道路 (road), 道路交叉路口 (intersection), 兴趣点 (point of interest), 门牌号
  (house number), 单元号 (unit), 公交地铁站点 (transit stop), 门址 (building entrance), 住宅区
  (residential area) or 未知 (unknown) — and the fields above it are filled in only as far
  as the match goes: a 区县 (district) match has no `street`.

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
