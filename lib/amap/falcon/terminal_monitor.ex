defmodule Amap.Falcon.TerminalMonitor do
  @moduledoc """
  A terminal's last known position.

  This is the one endpoint that answers with the position as a bare `"lon,lat"`
  string rather than an object — the search endpoints return the object form —
  so `location` here is a `{lon, lat}` tuple, parsed for you.

  ## Examples

  The examples are doctests: they run against a local stand-in, so they need no key
  and never call Amap. `base_urls` is the override the client documents for exactly
  that — a proxy or a local server — and a real call site omits it:
  `Amap.new(key: …)`. The stand-in's payloads are illustrative, not live readings.

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> {:ok, empty} = Amap.Falcon.TerminalMonitor.lastpoint(client, 1000, 456)
      iex> empty.location
      nil
      iex> {:ok, uploaded} =
      ...>   Amap.Falcon.TerminalMonitor.lastpoint(client, 1000, 456, correction: :n)
      iex> uploaded.location
      {114.158, 22.279}

  Under the default `correction: :driving` a short track can come back with no
  position at all — the call succeeds and `location` is `nil`, not a point — while
  `correction: :n` answers the point as it was uploaded. Either way `location` is a
  `{lon, lat}` tuple, parsed from the bare `"lon,lat"` string Amap sends here.

  A correction mode Amap does not document is refused rather than sent:

      iex> client =
      ...>   Amap.new(key: "test-key", base_urls: %{tsapi: "http://localhost:21617"})
      iex> Amap.Falcon.TerminalMonitor.lastpoint(client, 1000, 456, correction: :maybe)
      ** (ArgumentError) :correction must be :driving or :n, got: :maybe
  """

  alias Amap.Falcon.Position

  @base "/v1/track/terminal"

  @doc """
  Returns a terminal's last known position.

  `location` is a `{lon, lat}` tuple. Amap sends it as a bare `"lon,lat"` string,
  and that order was confirmed against the live API on 2026-09-17 by uploading a
  known track and reading it back.

  Amap requires at least five points before this answers at all.

  **The default `correction: :driving` snaps the track to roads and can return no
  data whatsoever for a short track.** A five-point, 120-metre track came back with
  an empty `data` under the default, and with the uploaded point under
  `correction: :n`. Pass `correction: :n` when you want the last point as it was
  uploaded rather than a road-snapped one.

  Fields may also carry values nobody sent: the same call reported `speed` 255,
  `direction` 511 and an `accuracy` of 550 metres for points that only had a
  location and a time.
  """
  @spec lastpoint(Amap.Client.t(), integer(), integer(), keyword()) ::
          {:ok, Position.t()} | {:error, Amap.Error.t()}
  def lastpoint(client, sid, tid, opts \\ []) do
    params = [
      sid: sid,
      tid: tid,
      trid: Keyword.get(opts, :trid),
      correction: correction_param(Keyword.get(opts, :correction))
    ]

    case Amap.request(client, :tsapi, :get, @base <> "/lastpoint", params) do
      {:ok, payload} -> {:ok, Position.from_payload(payload)}
      {:error, _} = error -> error
    end
  end

  defp correction_param(nil), do: nil
  defp correction_param(:driving), do: "driving"
  defp correction_param(:n), do: "n"

  defp correction_param(other),
    do: raise(ArgumentError, ":correction must be :driving or :n, got: #{inspect(other)}")
end
