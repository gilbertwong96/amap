defmodule Amap.Falcon.TrackAnalysis.StayPoints do
  @moduledoc """
  Where a trajectory stopped, and how many times.
  """

  alias Amap.Falcon.TrackAnalysis.StayPoint

  defstruct count: nil, points: []

  @type t :: %__MODULE__{
          count: integer() | nil,
          points: [StayPoint.t()]
        }
end
