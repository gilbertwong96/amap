defmodule Amap.Bus.Line.Stop do
  @moduledoc """
  A stop as a line lists it: its id, name, `{lon, lat}` position and its
  `sequence` on the line.

  The station endpoints answer with the richer `Amap.Bus.Stop` instead, which also
  carries the adcode, the citycode and the lines serving it.
  """

  defstruct [:id, :name, :location, :sequence]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          location: {float(), float()} | nil,
          sequence: String.t() | nil
        }
end
