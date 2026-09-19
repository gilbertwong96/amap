defmodule Amap.NewRoute.Tmc do
  @moduledoc """
  The traffic flow along one stretch — the `tmcs` group, which arrives only when
  `show_fields` asked for it.

  Its names are v5's own: this is `tmc_status` where v3 says `status`, `tmc_distance`
  where v3 says `distance`, and `tmc_polyline` — decoded here into `{lon, lat}` tuples
  — where v3 says `polyline`. The status arrives in Chinese (未知、畅通、缓行、拥堵、
  严重拥堵) and stays there, because it is a label rather than an enumeration this
  SDK can key on.
  """

  defstruct [:tmc_status, :tmc_distance, :tmc_polyline]

  @type t :: %__MODULE__{
          tmc_status: String.t() | nil,
          tmc_distance: String.t() | nil,
          tmc_polyline: [{float(), float()}] | nil
        }
end
