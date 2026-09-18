defmodule Amap.Falcon.TrackAnalysis.Section do
  @moduledoc """
  One kind of harsh event, as the list of points where it happened.
  """

  alias Amap.Falcon.TrackAnalysis.Event

  defstruct points: []

  @type t :: %__MODULE__{points: [Event.t()]}
end
