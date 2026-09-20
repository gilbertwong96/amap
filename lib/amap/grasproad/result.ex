defmodule Amap.Grasproad.Result do
  @moduledoc """
  A corrected driving track: how far it ran, and the road coordinates it follows.

  `distance` keeps whatever the wire sent. The page names neither a unit nor a type for
  it — only 总距离 — and the v4 generation's numbers differ from its v3 neighbours'
  strings, so nothing is converted here.
  """

  alias Amap.Grasproad.Point

  defstruct distance: nil, points: []

  @type t :: %__MODULE__{
          distance: String.t() | number() | nil,
          points: [Point.t()]
        }
end
