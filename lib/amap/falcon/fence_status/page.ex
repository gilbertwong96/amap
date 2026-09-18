defmodule Amap.Falcon.FenceStatus.Page do
  @moduledoc """
  One page of fence relations, plus Amap's count for the whole result set.
  """

  alias Amap.Falcon.FenceStatus

  defstruct items: [], count: nil

  @type t :: %__MODULE__{
          items: [FenceStatus.t()],
          count: integer() | nil
        }
end
