defmodule Amap.NewPlace.Business do
  @moduledoc """
  A v5 poi's 商业信息 (`business`), returned only when `show_fields` asks for it.

  The 关键字搜索 page lists `opentime_today`, `opentime_week`, `keytag` and `rectag`; the
  around, polygon and detail tables omit those four, so a call to one of them leaves them
  `nil`. Each field belongs to a kind of POI rather than to every POI — `rating` and `cost`
  to restaurants, hotels, sights and cinemas, `parking_type` to car parks — and the page
  says `alias` is absent when the POI has none.
  """

  defstruct [
    :business_area,
    :opentime_today,
    :opentime_week,
    :tel,
    :tag,
    :rating,
    :cost,
    :parking_type,
    :alias,
    :keytag,
    :rectag
  ]

  @type t :: %__MODULE__{
          business_area: String.t() | nil,
          opentime_today: String.t() | nil,
          opentime_week: String.t() | nil,
          tel: String.t() | nil,
          tag: String.t() | nil,
          rating: String.t() | nil,
          cost: String.t() | nil,
          parking_type: String.t() | nil,
          alias: String.t() | nil,
          keytag: String.t() | nil,
          rectag: String.t() | nil
        }
end
