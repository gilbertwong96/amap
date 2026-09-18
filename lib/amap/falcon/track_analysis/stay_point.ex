defmodule Amap.Falcon.TrackAnalysis.StayPoint do
  @moduledoc """
  One stop: when it began and ended, how long it lasted, where it was, and Amap's
  description of that place.
  """

  defstruct [:start_time, :end_time, :duration, :location, :address]

  @type t :: %__MODULE__{
          start_time: integer() | nil,
          end_time: integer() | nil,
          duration: integer() | nil,
          location: {float(), float()} | nil,
          address: String.t() | nil
        }
end
