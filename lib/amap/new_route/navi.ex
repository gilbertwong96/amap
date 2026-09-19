defmodule Amap.NewRoute.Navi do
  @moduledoc """
  What to tell the driver — the `navi` group, which arrives only when `show_fields`
  asked for it.

  `action` and `assistant_action` are Amap's own instructions (直行, 进入主路 and the
  rest of the two tables its page prints) and stay in Chinese. `walk_type` is the
  road-type code the same group carries — the 23 values from 0 普通道路 to 30 轮渡,
  gaps included — and stays the wire's string for the same reason as the statuses:
  the codes are Amap's, and a caller comparing one wants to compare it to the page.
  """

  defstruct [:action, :assistant_action, :walk_type]

  @type t :: %__MODULE__{
          action: String.t() | nil,
          assistant_action: String.t() | nil,
          walk_type: String.t() | nil
        }
end
