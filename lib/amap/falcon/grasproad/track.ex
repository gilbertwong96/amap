defmodule Amap.Falcon.Grasproad.Track do
  @moduledoc """
  One trace as `trsearch/4` reports it.

  `distance` is in metres and `time` is the duration in milliseconds, which is
  not the same as any point's `locatetime`.
  """

  alias Amap.Falcon.Position

  defstruct [:trid, :trname, :distance, :time, :counts, points: []]

  @type t :: %__MODULE__{
          trid: integer() | nil,
          trname: String.t() | nil,
          distance: number() | nil,
          time: integer() | nil,
          counts: integer() | nil,
          points: [Position.t()]
        }
end
