defmodule Amap.Weather.Cast do
  @moduledoc """
  One day of a forecast, split into its day and its night.

  `date` is `"2026-09-17"` and `week` is the day of the week as Amap numbers it.
  Temperatures are in °C and wind power on the Chinese 级 wind scale (0 to 17), all as
  strings.
  """

  defstruct [
    :date,
    :week,
    :dayweather,
    :nightweather,
    :daytemp,
    :nighttemp,
    :daywind,
    :nightwind,
    :daypower,
    :nightpower
  ]

  @type t :: %__MODULE__{
          date: String.t() | nil,
          week: String.t() | nil,
          dayweather: String.t() | nil,
          nightweather: String.t() | nil,
          daytemp: String.t() | nil,
          nighttemp: String.t() | nil,
          daywind: String.t() | nil,
          nightwind: String.t() | nil,
          daypower: String.t() | nil,
          nightpower: String.t() | nil
        }
end
