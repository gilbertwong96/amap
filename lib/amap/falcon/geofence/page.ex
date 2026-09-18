defmodule Amap.Falcon.Geofence.Page do
  @moduledoc """
  One page of geofences, plus Amap's count for the whole result set.
  """

  alias Amap.Falcon.Geofence

  defstruct items: [], count: nil

  @type t :: %__MODULE__{
          items: [Geofence.t()],
          count: integer() | nil
        }
end
