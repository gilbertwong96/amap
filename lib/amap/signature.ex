defmodule Amap.Signature do
  @moduledoc """
  Amap's digital signature.

  Per the official documentation, `sig` is the MD5 of all request parameters
  (including `key`) sorted by name, joined as `k1=v1&k2=v2&…`, with the private
  key appended. The request path is *not* part of the signed string, and values
  are signed raw — URL encoding happens later, when the request is sent.

  Signatures apply to the Web service family only. The Falcon documentation
  never mentions them, so this module is wired into `:restapi` requests only.
  """

  @doc """
  Computes `sig` for the given parameters.

  The `key` parameter is included by the caller, since Amap signs it too. Any
  `sig` already present is ignored. Keys and values are stringified, so a list
  that mixes an atom `:key` with the string keys `Amap.Param.encode/1` produces
  is signed exactly as the query string that gets sent.
  """
  @spec sign([{String.t() | atom(), String.t()}], String.t()) :: String.t()
  def sign(params, private_key) when is_list(params) and is_binary(private_key) do
    signed_string = Enum.map_join(sorted(params), "&", fn {k, v} -> k <> "=" <> v end)

    Base.encode16(:erlang.md5(signed_string <> private_key), case: :lower)
  end

  defp sorted(params) do
    params
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Enum.reject(fn {k, _v} -> k == "sig" end)
    |> Enum.sort_by(fn {k, _v} -> k end)
  end
end
