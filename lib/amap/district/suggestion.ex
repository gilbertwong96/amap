defmodule Amap.District.Suggestion do
  @moduledoc """
  The keywords and cities Amap suggests when a query matched nothing.

  Both are `[]` when Amap has no suggestion, which for a query that matched
  something is always.
  """

  defstruct keywords: [], cities: []

  @type t :: %__MODULE__{keywords: [String.t()], cities: [String.t()]}
end
