defmodule Amap.Falcon.Validate do
  @moduledoc """
  Call-site validation for Falcon parameters.

  Amap's naming rules and numeric ranges are documented, and breaking one costs a
  round trip that comes back as `20000` or `20001` with no way to tell which
  field was wrong. These raise instead, naming the field, before any request is
  built.
  """

  @max_name_length 128
  @charset ~r/^[\p{Han}A-Za-z0-9_-]+$/u

  @doc """
  Validates a name, a description, or a trace name.

  Per Amap: at most 128 characters, only Chinese, English letters, digits,
  underscore and hyphen, and it may not start with an underscore.
  """
  @spec name!(term(), String.t()) :: String.t()
  def name!(value, field) do
    cond do
      not is_binary(value) or value == "" ->
        raise ArgumentError, "#{field} must be a non-empty string"

      String.length(value) > @max_name_length ->
        raise ArgumentError,
              "#{field} must be at most #{@max_name_length} characters, got: #{String.length(value)}"

      String.starts_with?(value, "_") ->
        raise ArgumentError, "#{field} may not start with an underscore"

      not Regex.match?(@charset, value) ->
        raise ArgumentError, "#{field} may only contain Chinese, letters, digits, _ and -"

      true ->
        value
    end
  end

  @doc "Validates an integer parameter against Amap's documented interval."
  @spec range!(term(), String.t(), integer(), integer()) :: integer()
  def range!(value, field, min, max) do
    cond do
      not is_integer(value) ->
        raise ArgumentError, "#{field} must be an integer, got: #{inspect(value)}"

      value < min or value > max ->
        raise ArgumentError, "#{field} must be between #{min} and #{max}, got: #{value}"

      true ->
        value
    end
  end
end
