defmodule Amap.Direction.Tmc do
  @moduledoc """
  One stretch of road carrying the same traffic — a member of a path's or a step's
  `tmcs`.

  Amap writes these for driving only, and only when the call asked for
  `extensions: :all`. `status` is its own word for the flow — 畅通 (clear), 缓行
  (slow), 拥堵 (congested), 严重拥堵 (heavily congested) or 未知 (unknown) — and stays in
  Chinese, so a caller that displays it needs no lookup.

  `polyline` is the stretch's points as a flat list of `{lon, lat}` tuples, the same
  shape a step's own polyline takes.

  The third live run's elements also carried an `lcode` key — `nil` in all four — which no
  struct here reads: a v3 stretch can arrive with one, and nothing is claimed about what
  a non-nil value would mean until a run or a page shows it.
  """

  defstruct [:distance, :status, :polyline]

  @type t :: %__MODULE__{
          distance: String.t() | nil,
          status: String.t() | nil,
          polyline: [{float(), float()}] | nil
        }
end
