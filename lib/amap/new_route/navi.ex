defmodule Amap.NewRoute.Navi do
  @moduledoc """
  What to tell the driver — the `navi` group, which arrives only when `show_fields`
  asked for it.

  `action` and `assistant_action` are Amap's own instructions (直行, 进入主路 and the
  rest of the two tables its page prints) and stay in Chinese.

  **`walk_type` is not here**: it is its own `show_fields` group and a field of
  `Amap.NewRoute.Step`. The page prints it at the same level as `polyline`, a group,
  while this group's children are only the two instructions above.
  """

  defstruct [:action, :assistant_action]

  @type t :: %__MODULE__{
          action: String.t() | nil,
          assistant_action: String.t() | nil
        }
end
