defmodule Amap.Falcon.TerminalMonitor.Position do
  @moduledoc """
  A terminal's last known position, as the monitoring endpoint reports it.

  Every field is optional: Amap may omit the time, accuracy, direction, speed and
  height when it snaps the track to roads.
  """

  defstruct [:location, :locatetime, :accuracy, :direction, :speed, :height, :props]

  @type t :: %__MODULE__{
          location: {float(), float()} | nil,
          locatetime: integer() | nil,
          accuracy: number() | nil,
          direction: number() | nil,
          speed: number() | nil,
          height: number() | nil,
          props: map() | nil
        }
end
