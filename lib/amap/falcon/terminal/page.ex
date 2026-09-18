defmodule Amap.Falcon.Terminal.Page do
  @moduledoc """
  One page of terminals, plus Amap's count for the whole result set.
  """

  alias Amap.Falcon.Terminal

  defstruct items: [], count: nil

  @type t :: %__MODULE__{
          items: [Terminal.t()],
          count: integer() | nil
        }
end
