defmodule Amap.Place.Poi do
  @moduledoc """
  One POI from a v3 搜索POI answer.

  The fields are the page's shared response tree. Which of them arrive depends on the
  call: `distance` is 周边搜索's (离中心点距离), and the fields the tree marks
  `extensions=all` — `website`, `email`, the province/city/adcode group, the entrance and
  exit, `navi_poiid`, `gridcode`, `alias`, `parking_type`, `tag`, the indoor block,
  `business_area`, `biz_ext`, `photos` — arrive only when the call asked for `all`.
  Anything Amap left out is `nil`, or `[]` for `photos`.

  The v5 page nests several of these under `business` and `indoor`
  (`Amap.NewPlace.Poi`), which is the pages' difference rather than a shape this struct
  chose.
  """

  alias Amap.Place.BizExt
  alias Amap.Place.IndoorData
  alias Amap.Place.Photo

  defstruct [
    :id,
    :parent,
    :name,
    :type,
    :typecode,
    :biz_type,
    :address,
    :location,
    :distance,
    :tel,
    :postcode,
    :website,
    :email,
    :pcode,
    :pname,
    :citycode,
    :cityname,
    :adcode,
    :adname,
    :entr_location,
    :exit_location,
    :navi_poiid,
    :gridcode,
    :alias,
    :parking_type,
    :tag,
    :indoor_map,
    :indoor_data,
    :groupbuy_num,
    :business_area,
    :atag,
    :discount_num,
    :biz_ext,
    photos: []
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          parent: String.t() | nil,
          name: String.t() | nil,
          type: String.t() | nil,
          typecode: String.t() | nil,
          biz_type: String.t() | nil,
          address: String.t() | nil,
          location: {float(), float()} | nil,
          distance: String.t() | nil,
          tel: String.t() | nil,
          postcode: String.t() | nil,
          website: String.t() | nil,
          email: String.t() | nil,
          pcode: String.t() | nil,
          pname: String.t() | nil,
          citycode: String.t() | nil,
          cityname: String.t() | nil,
          adcode: String.t() | nil,
          adname: String.t() | nil,
          entr_location: {float(), float()} | nil,
          exit_location: {float(), float()} | nil,
          navi_poiid: String.t() | nil,
          gridcode: String.t() | nil,
          alias: String.t() | nil,
          parking_type: String.t() | nil,
          tag: String.t() | nil,
          indoor_map: String.t() | nil,
          indoor_data: IndoorData.t() | nil,
          groupbuy_num: String.t() | nil,
          business_area: String.t() | nil,
          atag: String.t() | nil,
          discount_num: String.t() | nil,
          biz_ext: BizExt.t() | nil,
          photos: [Photo.t()]
        }
end
