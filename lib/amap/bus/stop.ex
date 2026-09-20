defmodule Amap.Bus.Stop do
  @moduledoc """
  A bus stop, as the two station endpoints answer with it.

  `location` is the `{lon, lat}` tuple decoded from Amap's `"lon,lat"` string.
  `buslines` holds the lines serving this stop — each a summary rather than
  `Amap.Bus.Line`: the station endpoints send five fields per line, while the
  line endpoints send a line's full record.
  """

  alias Amap.Bus.Stop.Busline

  defstruct [:id, :name, :location, :adcode, :citycode, buslines: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          location: {float(), float()} | nil,
          adcode: String.t() | nil,
          citycode: String.t() | nil,
          buslines: [Busline.t()]
        }
end
