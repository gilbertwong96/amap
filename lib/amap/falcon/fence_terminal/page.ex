defmodule Amap.Falcon.FenceTerminal.Page do
  @moduledoc """
  One page of bound terminals, plus Amap's count for the whole result set.
  """

  alias Amap.Falcon.FenceTerminal

  defstruct items: [], count: nil

  @type t :: %__MODULE__{
          items: [FenceTerminal.t()],
          count: integer() | nil
        }
end
