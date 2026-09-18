defmodule Amap.Falcon.TerminalMonitor do
  @moduledoc """
  A terminal's last known position.

  This is the one endpoint that answers with the position as a bare `"lon,lat"`
  string rather than an object — the search endpoints return the object form —
  so `location` here is a `{lon, lat}` tuple, parsed for you.
  """

  alias Amap.Falcon.TerminalMonitor.Position
  alias Amap.Numeric

  @base "/v1/track/terminal"

  @doc """
  Returns a terminal's last known position.

  Amap requires at least five continuous points before this answers at all. With
  the default `correction: :driving`, which snaps the track to roads, the reply
  may omit the time, accuracy, direction, speed and height entirely — which is
  why every field is optional.
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
      {:ok, payload} -> {:ok, to_position(payload)}
      {:error, _} = error -> error
    end
  end

  defp correction_param(nil), do: nil
  defp correction_param(:driving), do: "driving"
  defp correction_param(:n), do: "n"

  defp correction_param(other),
    do: raise(ArgumentError, ":correction must be :driving or :n, got: #{inspect(other)}")

  defp to_position(payload) do
    %Position{
      location: parse_location(payload["location"]),
      locatetime: Numeric.to_integer(payload["locatetime"]),
      accuracy: payload["accuracy"],
      direction: payload["direction"],
      speed: payload["speed"],
      height: payload["height"],
      props: payload["props"]
    }
  end

  # Amap documents only "X,Y" here, with no example, so the order is inferred
  # from the upload endpoint (longitude first). Task 9's live run settles it.
  defp parse_location(nil), do: nil

  defp parse_location(string) when is_binary(string) do
    with [lon, lat] <- String.split(string, ","),
         {lon, ""} <- Float.parse(lon),
         {lat, ""} <- Float.parse(lat) do
      {lon, lat}
    else
      _unparseable -> nil
    end
  end

  defp parse_location(_other), do: nil
end
