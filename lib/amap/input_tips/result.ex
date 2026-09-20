defmodule Amap.InputTips.Result do
  @moduledoc """
  What a 输入提示 query answered: the tips and Amap's count.

  `count` stays the string Amap sent; its page calls it 返回结果总数目 while the two place
  searches' pages call the same field something else again. The rows live in `tips`, never
  `nil`, so a caller can map over them without a nil check.
  """

  alias Amap.InputTips.Tip

  defstruct [:count, tips: []]

  @type t :: %__MODULE__{count: String.t() | nil, tips: [Tip.t()]}
end
