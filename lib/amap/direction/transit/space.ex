defmodule Amap.Direction.Transit.Space do
  @moduledoc """
  A seat class and its fare — a member of an alternative's `spaces`.

  `code` is Amap's 仓位级别 and stays a string, so `"9"` never reads as an index:
  `"0"` is 不分仓位级别, `"9"` 特等座, `"10"` 火车硬座, `"20"` 火车高级软卧下铺, `"30"`
  飞机经济舱 and `"43"` 客轮豪华舱 are examples. The page's own table runs 0–43 with
  gaps in it, so the codes are not sequential and not every number is a class.

  `cost` is the fare in yuan, also a string — `"553.0"` is a price Amap wrote, not a
  number to do arithmetic in.
  """

  defstruct [:code, :cost]

  @type t :: %__MODULE__{
          code: String.t() | nil,
          cost: String.t() | nil
        }
end
