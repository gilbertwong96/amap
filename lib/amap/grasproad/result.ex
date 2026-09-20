defmodule Amap.Grasproad.Result do
  @moduledoc """
  A corrected driving track: how far it ran, and the road coordinates it follows.

  `distance` keeps whatever the wire sent. The page names neither a unit nor a type for
  it — only 总距离 — and the live run sees a **float** (`696.0`) here: the
  `/v4/`-on-`restapi` endpoints' numeric shape, unlike the string distances the v3 and
  v5 routing pages send. Nothing is converted.

  `points` is the corrected track itself. Amap **densifies** it — the run sent 8 points
  and got 28 back — so their count is not the count of points sent.
  """

  alias Amap.Grasproad.Point

  defstruct distance: nil, points: []

  @type t :: %__MODULE__{
          distance: String.t() | number() | nil,
          points: [Point.t()]
        }
end
