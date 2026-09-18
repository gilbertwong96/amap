defmodule Amap.Weather.Forecast do
  @moduledoc """
  预报天气 — a city's forecast, three days at a time.

  `casts` holds one entry per day in Amap's own order, and `reporttime` is when
  the forecast was issued rather than the day it describes.
  """

  alias Amap.Weather.Cast

  defstruct [:city, :adcode, :province, :reporttime, casts: []]

  @type t :: %__MODULE__{
          city: String.t() | nil,
          adcode: String.t() | nil,
          province: String.t() | nil,
          reporttime: String.t() | nil,
          casts: [Cast.t()]
        }
end
