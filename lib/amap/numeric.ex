defmodule Amap.Numeric do
  @moduledoc """
  Coercion for the numbers Amap's envelopes carry.

  Both families put codes and counters on the wire as a JSON number in some
  responses and as a string in others, so anything reading them has to accept
  either shape. The coercions here are deliberately total: a value that is
  neither an integer nor a string of digits becomes `nil` rather than raising,
  so a malformed envelope surfaces as an Amap error instead of a crash. Do not
  replace them with `String.to_integer/1`, which raises.
  """

  @doc """
  An integer, from either an integer or a string of digits.

  Returns `nil` for anything else, including strings that are only partly
  numeric such as `"10001 "` or `"1.5"`.
  """
  @spec to_integer(Amap.JSON.value()) :: integer() | nil
  def to_integer(value) when is_integer(value), do: value

  def to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def to_integer(_value), do: nil
end
