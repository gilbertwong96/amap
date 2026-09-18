defmodule Amap.Falcon.Point.UploadError do
  @moduledoc """
  One point Amap refused.

  `index` is the point's position in the batch that was sent, one-based, and
  arrives from Amap as a string. `raw` keeps whatever else came with it, so a
  field this struct does not model is still visible.
  """

  defstruct [:index, :message, raw: %{}]

  @type t :: %__MODULE__{
          index: String.t() | nil,
          message: String.t() | nil,
          raw: map()
        }
end
