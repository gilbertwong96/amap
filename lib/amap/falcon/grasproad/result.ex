defmodule Amap.Falcon.Grasproad.Result do
  @moduledoc """
  What `trsearch/4` read: the traces it found, and how much Amap had to degrade
  the parameters to answer.
  """

  alias Amap.Falcon.Grasproad.Degraded
  alias Amap.Falcon.Grasproad.Track

  defstruct counts: nil, tracks: [], degraded_params: nil

  @type t :: %__MODULE__{
          counts: integer() | nil,
          tracks: [Track.t()],
          degraded_params: Degraded.t() | nil
        }
end
