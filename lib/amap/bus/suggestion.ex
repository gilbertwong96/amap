defmodule Amap.Bus.Suggestion do
  @moduledoc """
  The keywords and cities Amap suggests on the two keyword searches.

  Both are `[]` when Amap has no suggestion, which is every probe this service has
  answered so far — including a nationwide `linename` search. This carries exactly
  what the bus wire has shown; the search batch may own a richer type later.
  """

  defstruct keywords: [], cities: []

  @type t :: %__MODULE__{keywords: [String.t()], cities: [String.t()]}
end
