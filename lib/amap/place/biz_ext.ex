defmodule Amap.Place.BizExt do
  @moduledoc """
  A v3 POI's 深度信息 (`biz_ext`), which `extensions=all` carries.

  Every field belongs to a kind of POI rather than to every POI — the rating and the cost
  to restaurants, hotels, sights and cinemas; the four ordering flags to a meal, a seat, a
  ticket or a room — and the page marks the four flags 逐渐废弃 (gradually deprecated).
  Absent ones are `nil`.
  """

  defstruct [
    :rating,
    :cost,
    :meal_ordering,
    :seat_ordering,
    :ticket_ordering,
    :hotel_ordering
  ]

  @type t :: %__MODULE__{
          rating: String.t() | nil,
          cost: String.t() | nil,
          meal_ordering: String.t() | nil,
          seat_ordering: String.t() | nil,
          ticket_ordering: String.t() | nil,
          hotel_ordering: String.t() | nil
        }
end
