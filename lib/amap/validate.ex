defmodule Amap.Validate do
  @moduledoc """
  Call-site validation for Amap parameters.

  Amap's naming rules and numeric ranges are documented, and breaking one costs a
  round trip that comes back as `20000` or `20001` with no way to tell which
  field was wrong. These raise instead, naming the field, before any request is
  built.

  `name!` and `text!` are the narrower pair: the 128-character rule over Chinese,
  letters, digits, `_` and `-` is what Amap's **track** (Falcon) pages require of
  a name or a description. It does not apply to a Web-service address, a district
  keyword or a road name, so the Web-service modules do not call them.
  """

  @max_name_length 128
  @charset ~r/^[\p{Han}A-Za-z0-9_-]+$/u

  @typedoc """
  A value a call site may pass as a parameter.

  A validator exists to reject what Amap will not take, so what it accepts is
  whatever was written rather than the type the field must eventually be: an atom
  where a string belongs, a float where an integer does, a list where a pair does.
  This is that union — no pids, refs, ports or funs, which are not parameters.
  """
  @type input ::
          String.t()
          | number()
          | boolean()
          | atom()
          | {input(), input()}
          | {input(), input(), input()}
          | [input()]
          | %{optional(atom() | String.t()) => input()}
          | nil

  @doc """
  Validates a name, a description, or a trace name.

  Per Amap's track pages: at most 128 characters, only Chinese, English letters, digits,
  underscore and hyphen, and it may not start with an underscore. Empty is not a
  name, so this rejects it — `text!/2` is the variant for fields that an update
  can clear.
  """
  @spec name!(input(), String.t()) :: String.t()
  def name!(value, field) do
    if is_binary(value) and value != "" do
      text!(value, field)
    else
      raise ArgumentError, "#{field} must be a non-empty string"
    end
  end

  @doc """
  Validates a text field that an update may clear.

  Amap's update endpoints document this: a field that is given but left empty
  **clears** the stored value, which is different from leaving it out entirely.
  The character and length rules still apply; only emptiness is allowed.
  """
  @spec text!(input(), String.t()) :: String.t()
  def text!(value, field) do
    cond do
      not is_binary(value) ->
        raise ArgumentError, "#{field} must be a string"

      String.length(value) > @max_name_length ->
        raise ArgumentError,
              "#{field} must be at most #{@max_name_length} characters, got: #{String.length(value)}"

      value == "" ->
        value

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
  @spec present!(input(), String.t()) :: String.t()
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
  @spec optional!((input(), String.t() -> String.t()), input(), String.t()) :: String.t() | nil
  def optional!(_validator, nil, _field), do: nil
  def optional!(validator, value, field), do: validator.(value, field)

  @doc """
  Validates an optional integer against Amap's documented interval.

  `nil` means the parameter was left out and stays out of the request, which is the
  shape every endpoint's `page`, `pagesize` and threshold options share.
  """
  @spec optional_range!(input(), String.t(), integer(), integer()) :: integer() | nil
  def optional_range!(nil, _field, _min, _max), do: nil
  def optional_range!(value, field, min, max), do: range!(value, field, min, max)

  @doc """
  Validates an optional value against the set Amap documents, for the parameters
  that take `base`/`all` or a list of systems.

  Returns the string to send, or `nil` when the caller left the parameter out.
  An undocumented value raises instead of reaching Amap, which would answer a
  value it does not know with something that looks like an answer.
  """
  @spec optional_enum!(input(), String.t(), [atom()]) :: String.t() | nil
  def optional_enum!(nil, _field, _allowed), do: nil

  def optional_enum!(value, field, allowed) when is_atom(value) do
    if value in allowed do
      Atom.to_string(value)
    else
      raise ArgumentError, enum_message(value, field, allowed)
    end
  end

  def optional_enum!(value, field, allowed),
    do: raise(ArgumentError, enum_message(value, field, allowed))

  defp enum_message(value, field, allowed),
    do: "#{field} must be one of #{inspect(allowed)}, got: #{inspect(value)}"

  @doc """
  Validates a non-empty list of `{lon, lat}` pairs.

  Amap takes coordinates as pairs of numbers everywhere, so a list of lists, a
  pair of strings or a triple is a call-site mistake rather than a request.
  """
  @spec points!(input(), String.t()) :: [{number(), number()}]
  def points!(values, field) when is_list(values) and values != [] do
    Enum.each(values, &point!(&1, field))
    values
  end

  def points!(value, field),
    do:
      raise(
        ArgumentError,
        "#{field} must be a non-empty list of {lon, lat} pairs, got: #{inspect(value)}"
      )

  @doc "Validates one `{lon, lat}` pair."
  @spec point!(input(), String.t()) :: {number(), number()}
  def point!({lon, lat} = point, _field) when is_number(lon) and is_number(lat), do: point

  def point!(value, field),
    do:
      raise(
        ArgumentError,
        "#{field} must be a {lon, lat} pair of numbers, got: #{inspect(value)}"
      )

  @doc "Validates an integer parameter against Amap's documented interval."
  @spec range!(input(), String.t(), integer(), integer()) :: integer()
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
