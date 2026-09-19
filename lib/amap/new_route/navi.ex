defmodule Amap.NewRoute.Navi do
  @moduledoc """
  What to tell the traveller — the `navi` group, which arrives only when
  `show_fields` asked for it.

  `action` and `assistant_action` are Amap's own instructions (直行, 进入主路 and the
  rest of the two tables its page prints) and stay in Chinese.

  **`walk_type` arrives inside this object**, as Amap's road-type code (0 普通道路 …
  30 轮渡, gaps included) kept as the wire's string the way the statuses are. The v5
  page prints `walk_type` as a `show_fields` group of its own, which reads as a
  step-level field, but the wire puts it here: the live run found it inside `navi` on
  every step and flat on none, so the page's rule that each group is named after the
  field it controls is a rule this field does not follow.
  """

  defstruct [:action, :assistant_action, :walk_type]

  @type t :: %__MODULE__{
          action: String.t() | nil,
          assistant_action: String.t() | nil,
          walk_type: String.t() | nil
        }
end
