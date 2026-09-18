defmodule Amap.Falcon.Correction do
  @moduledoc """
  Amap's `correction` mini-format, and the rules for a trajectory time window.

  `correction` is not a value but a string of settings
  (`denoise=1,mapmatch=0,attribute=0,threshold=0,mode=driving`). Callers pass a
  keyword list, anything they leave out takes Amap's documented default, and the
  output is always in that documented order so it can be asserted on.

      correction: [mapmatch: true, threshold: 20]

  `window!/4` is the rule `Amap.Falcon.Grasproad.trsearch/4` has to satisfy: Amap
  wants either a trace id, or a window of at most 24 hours that does not end in
  the future.
  """

  @defaults [denoise: true, mapmatch: false, attribute: false, threshold: 0, mode: :driving]

  @doc """
  Encodes `correction` options, filling Amap's defaults.

  `nil` means "leave the parameter out" and lets the service apply its own
  defaults. An unknown key raises rather than being silently dropped.
  """
  @spec encode(keyword() | nil) :: String.t() | nil
  def encode(nil), do: nil

  def encode(opts) when is_list(opts) do
    # `Keyword.validate!/2` rejects unknown keys and fills the defaults, but it
    # does not keep the defaults' order, so the output is built from @defaults.
    validated = Keyword.validate!(opts, @defaults)

    Enum.map_join(@defaults, ",", fn {key, _default} -> "#{key}=#{value(key, validated[key])}" end)
  end

  defp value(_key, true), do: "1"
  defp value(_key, false), do: "0"
  defp value(:threshold, n) when is_integer(n) and n >= 0, do: Integer.to_string(n)
  defp value(:mode, mode) when mode in [:driving, :riding, :walking], do: to_string(mode)

  defp value(key, other),
    do: raise(ArgumentError, "unsupported correction value for #{key}: #{inspect(other)}")

  @doc """
  Checks that a `trsearch` call says what to read.

  Amap wants either a `trid` or a full `starttime`/`endtime` window; the window
  may be at most 24 hours and may not end in the future.
  """
  @spec window!(integer() | nil, integer() | nil, integer() | nil, integer()) :: :ok
  def window!(trid, starttime, endtime, now) do
    cond do
      trid != nil and (starttime != nil or endtime != nil) ->
        raise ArgumentError, "pass either :trid or a :starttime/:endtime window, not both"

      trid != nil ->
        :ok

      is_integer(starttime) and is_integer(endtime) ->
        if endtime - starttime > 24 * 60 * 60 * 1000 do
          raise ArgumentError,
                "the window may not exceed 24 hours, got #{(endtime - starttime) / 3_600_000} hours"
        end

        if endtime > now do
          raise ArgumentError, "the window may not end in the future"
        end

        :ok

      true ->
        raise ArgumentError, "trsearch needs either :trid or both :starttime and :endtime"
    end
  end
end
