defmodule Amap.Falcon.Grasproad.RoadResult do
  @moduledoc """
  What `roaddata/2` read: the road attributes of a trajectory.
  """

  alias Amap.Falcon.Grasproad.RoadTrack

  defstruct counts: nil, distance: nil, tracks: []

  @type t :: %__MODULE__{
          counts: integer() | nil,
          distance: number() | nil,
          tracks: [RoadTrack.t()]
        }
end
