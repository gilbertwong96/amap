defmodule Amap.JSON do
  @moduledoc """
  The one place the SDK reaches for a JSON implementation.

  `encode!/1` is required in addition to `decode/1` because Falcon's `props`
  parameter carries a JSON object as a form value.

  The configured module is read at call time, not at compile time, so
  `config/runtime.exs` works and swapping libraries does not force a
  recompilation of this dependency.
  """

  @default JSON

  @typedoc """
  A value JSON can carry, and therefore one a decoded payload can carry.

  A parser is asked to survive whatever the service sent, which is this union and
  not `term()`: a payload holds no pids, refs, ports, funs or structs.
  """
  @type value ::
          String.t() | number() | boolean() | nil | [value()] | %{optional(String.t()) => value()}

  @typedoc "A JSON object: a payload's nested objects, and a Falcon page's rows."
  @type object :: %{optional(String.t()) => value()}

  @typedoc """
  A JSON object as a caller writes one — the `props` a request may carry.

  Atoms are allowed as keys because a caller reaching for `%{plate: "AB1234"}` is
  writing an object either way, and the configured encoder takes both.
  """
  @type props :: %{optional(String.t() | atom()) => value()}

  @typedoc """
  A module with `decode/1` and `encode!/1` — whichever JSON implementation is in
  use, which is why this one is as wide as a module and no wider.
  """
  @type library :: module()

  @spec decode(binary()) :: {:ok, value()} | {:error, binary()}
  def decode(binary), do: json_library().decode(binary)

  @spec encode!(value()) :: binary()
  def encode!(term), do: json_library().encode!(term)

  @spec json_library() :: library()
  def json_library, do: Application.get_env(:amap, :json_library, @default)
end
