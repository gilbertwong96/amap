defmodule Amap.Falcon.TerminalSearch.Page do
  @moduledoc """
  One page of search results, plus Amap's count for the whole result set.
  """

  alias Amap.Falcon.TerminalSearch.Result

  defstruct items: [], count: nil

  @type t :: %__MODULE__{
          items: [Result.t()],
          count: integer() | nil
        }
end
