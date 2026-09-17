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

  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(binary), do: json_library().decode(binary)

  @spec encode!(term()) :: binary()
  def encode!(term), do: json_library().encode!(term)

  @spec json_library() :: module()
  def json_library, do: Application.get_env(:amap, :json_library, @default)
end
