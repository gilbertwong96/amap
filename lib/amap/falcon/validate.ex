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

  @doc """
  Validates that a required string is present.

  For parameters whose contents Amap does not restrict — a search keyword, for
  instance — where emptiness is the only caller mistake worth catching.
  """
  @spec present!(term(), String.t()) :: String.t()
  def present!(value, field) do
    if is_binary(value) and value != "" do
      value
    else
      raise ArgumentError, "#{field} must be a non-empty string"
    end
  end

  @doc """
  Validates a value only when it was given.

  Optional parameters arrive as `nil` when the caller left them out, and
  `nil` is not a valid value to check — it means "absent", which the encoder
  turns into a missing parameter rather than an empty one.
  """
  @spec optional!((term(), String.t() -> String.t()), term(), String.t()) :: String.t() | nil
  def optional!(_validator, nil, _field), do: nil
  def optional!(validator, value, field), do: validator.(value, field)

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
