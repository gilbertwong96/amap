defmodule Amap.Falcon.Wire do
  @moduledoc """
  Amap's wire spellings that more than one module needs.

  These are the values Amap writes in its own dialect rather than as the thing
  they mean: identifiers as one comma-separated parameter, flags as `1` and `0`,
  and `"#all"` as a sentinel for "every one of them". Both directions live here,
  so the encoding and the decoding of a flag cannot be confused for each other.
  """

  alias Amap.Falcon.Validate

  @max_ids 100

  @doc """
  Encodes a list of ids, or the `:all` sentinel.

  Amap keeps the first 100 ids of a longer list and answers success, so a caller
  who passed 150 would believe all of them were acted on. This raises instead.
  """
  @spec ids!([integer()] | :all, String.t()) :: String.t()
  def ids!(:all, _field), do: "#all"

  def ids!(ids, field) when is_list(ids) do
    Validate.range!(length(ids), field, 1, @max_ids)
    Enum.map_join(ids, ",", &to_string/1)
  end

  @doc """
  Decodes a list of ids Amap answered with.

  Amap omits the list entirely for the `#all` case, so `nil` and an empty list
  both come back empty, and ids arriving as strings become integers.
  """
  @spec decode_ids(term()) :: [integer()]
  def decode_ids(ids) do
    ids
    |> List.wrap()
    |> Enum.map(&to_id/1)
  end

  @doc """
  Encodes an optional boolean the way Amap writes flags.

  `nil` means the option was left out and stays out of the request; Amap omits a
  flag rather than sending a false one.
  """
  @spec flag!(term()) :: String.t() | nil
  def flag!(nil), do: nil
  def flag!(true), do: "1"
  def flag!(false), do: "0"
  def flag!(other), do: raise(ArgumentError, "expected a boolean, got: #{inspect(other)}")

  @doc """
  Decodes a flag Amap answered with.

  Amap writes `1` and `0`, and a missing field means the same as `nil` rather
  than false.
  """
  @spec decode_flag(term()) :: boolean() | nil
  def decode_flag(nil), do: nil
  def decode_flag(0), do: false
  def decode_flag(1), do: true
  def decode_flag("0"), do: false
  def decode_flag("1"), do: true
  def decode_flag(_other), do: nil

  defp to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _other -> id
    end
  end

  defp to_id(id), do: id
end
