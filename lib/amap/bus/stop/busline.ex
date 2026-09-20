defmodule Amap.Bus.Stop.Busline do
  @moduledoc """
  A line as it appears inside a stop: its id, its position at this stop, its
  name, and its two terminals.

  This is the **summary** the station endpoints send, not `Amap.Bus.Line`. Its
  `name` carries the route plus its terminals — `"854路(望京西枢纽站--孙河公交场站)"` —
  and `start_stop`/`end_stop` repeat that half of it, as the service sends them.
  """

  defstruct [:id, :location, :name, :start_stop, :end_stop]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          location: {float(), float()} | nil,
          name: String.t() | nil,
          start_stop: String.t() | nil,
          end_stop: String.t() | nil
        }
end
