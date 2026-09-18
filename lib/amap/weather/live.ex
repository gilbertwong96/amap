defmodule Amap.Weather.Live do
  @moduledoc """
  实况天气 — what the weather is doing in a city right now.

  Every field is a string, which is the form Amap writes them in: `temperature` in
  °C, `windpower` on Amap's Chinese 级 wind scale, `humidity` in percent, and `reporttime`
  when Amap measured it (`"2026-09-17 14:00:00"`).
  """

  defstruct [
    :province,
    :city,
    :adcode,
    :weather,
    :temperature,
    :winddirection,
    :windpower,
    :humidity,
    :reporttime
  ]

  @type t :: %__MODULE__{
          province: String.t() | nil,
          city: String.t() | nil,
          adcode: String.t() | nil,
          weather: String.t() | nil,
          temperature: String.t() | nil,
          winddirection: String.t() | nil,
          windpower: String.t() | nil,
          humidity: String.t() | nil,
          reporttime: String.t() | nil
        }
end
