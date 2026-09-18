defmodule Amap.Falcon.Point.Upload do
  @moduledoc """
  The result of uploading a batch of points.

  An empty `errorpoints` means every point was stored. Amap answers `20100` when
  only some were, and still stores the rest — which is why an upload with a
  non-empty list is a successful call whose data says what to retry.
  """

  alias Amap.Falcon.Point.UploadError

  defstruct errorpoints: []

  @type t :: %__MODULE__{
          errorpoints: [UploadError.t()]
        }
end
