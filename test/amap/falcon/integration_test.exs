defmodule Amap.Falcon.IntegrationTest do
  @moduledoc """
  Live checks against Amap, for the facts documentation could not settle.

  Excluded by default (`test_helper.exs`). Run with a key:

      AMAP_KEY=… mix test --only integration test/amap/falcon/integration_test.exs

  What the runs have established so far:

    * a Falcon POST is accepted with `key` in the form body;
    * `terminal/list` sends `tid` as an integer and `name` as a string — the
      official response table for that endpoint says the opposite and is wrong;
    * Falcon's success code is `10000`, not only `0` (see `Amap.Response`).

  Still open, and what this test observes rather than asserts:

    * whether `TerminalSearch` can find a terminal by name before that terminal
      has ever reported a position. A freshly created terminal returned `count: 0`,
      so the test searches before and after uploading points and prints both.
      It asserts only that the calls succeed — a zero count is a fact about Amap's
      search semantics, not a defect in this SDK, and a rejected parameter would
      have come back as an error instead.
    * `lastpoint`'s `"X,Y"` order, inferred from the upload endpoint. The
      assertion below is what would catch a reversal.

  The upload steps call `Amap.request/5` directly because `point/upload` belongs
  to batch S2b, and a terminal needs at least five points before `lastpoint`
  answers at all.
  """

  use ExUnit.Case, async: false

  alias Amap.Falcon.Service
  alias Amap.Falcon.Terminal
  alias Amap.Falcon.TerminalMonitor
  alias Amap.Falcon.TerminalSearch

  @moduletag :integration
  @moduletag timeout: 60_000

  # .exs files are loaded on every run, so setting AMAP_KEY and re-running is
  # enough; without one the module skips rather than failing.
  if System.get_env("AMAP_KEY") in [nil, ""] do
    @moduletag :skip
  end

  setup do
    client = Amap.new(key: System.fetch_env!("AMAP_KEY"))
    {:ok, client: client}
  end

  test "a service, a terminal, a search and a real position", %{client: client} do
    name = "sdk_it_#{System.unique_integer([:positive])}"

    assert {:ok, service} = Service.add(client, name, desc: "集成测试")
    assert is_integer(service.sid)
    sid = service.sid

    on_exit(fn ->
      # Best effort: nothing may exist if the test failed early.
      case Terminal.list(client, sid) do
        {:ok, %{items: items}} ->
          Enum.each(items, fn t -> Terminal.delete(client, sid, t.tid) end)

        _other ->
          :ok
      end

      Service.delete(client, sid)
    end)

    assert {:ok, terminal} = Terminal.add(client, sid, name)
    assert is_integer(terminal.tid)
    tid = terminal.tid

    # Confirms the list response's real types, and whether a terminal that has
    # never reported a position is findable at all.
    assert {:ok, %Terminal.Page{items: [listed]}} = Terminal.list(client, sid)
    assert listed.tid == tid

    report("terminal/list", fn ->
      "types -> tid: #{inspect(listed.tid)} (#{type_of(listed.tid)}), " <>
        "name: #{inspect(listed.name)} (#{type_of(listed.name)}), " <>
        "createtime: #{type_of(listed.createtime)}, locatetime: #{type_of(listed.locatetime)}"
    end)

    assert {:ok, %TerminalSearch.Page{} = before_points} =
             TerminalSearch.search(client, sid, name)

    report("search before any position", fn -> "count: #{inspect(before_points.count)}" end)

    # Five points, one second apart and in the past, so the track looks ordinary.
    assert {:ok, trace} =
             Amap.request(client, :tsapi, :post, "/v1/track/trace/add", sid: sid, tid: tid)

    trid = trace["trid"]
    now = System.system_time(:millisecond)

    points =
      for n <- 0..4 do
        %{
          "location" => "#{114.158 + n / 100_000},#{22.279 + n / 100_000}",
          "locatetime" => now - (4 - n) * 1000
        }
      end

    assert {:ok, _} =
             Amap.request(client, :tsapi, :post, "/v1/track/point/upload",
               sid: sid,
               tid: tid,
               trid: trid,
               points: Amap.JSON.encode!(points)
             )

    position = await_lastpoint(client, sid, tid, 5)

    report("lastpoint", fn ->
      "location: #{inspect(position.location)} (first element #{type_of(elem(position.location, 0))})"
    end)

    # Hong Kong coordinates: longitude near 114, latitude near 22. If the parsed
    # tuple is reversed, this is what says so.
    {first, second} = position.location
    assert first > 90, "expected longitude first, got #{inspect(position.location)}"
    assert second < 90, "expected latitude second, got #{inspect(position.location)}"

    assert {:ok, %TerminalSearch.Page{} = after_points} =
             TerminalSearch.search(client, sid, name)

    report("search after a position exists", fn -> "count: #{inspect(after_points.count)}" end)

    assert {:ok, %TerminalSearch.Page{} = around} =
             TerminalSearch.aroundsearch(client, sid, {114.158, 22.279}, radius: 1000)

    report("aroundsearch within 1km", fn -> "count: #{inspect(around.count)}" end)
  end

  # Amap needs the points to land before lastpoint will answer; a couple of
  # seconds is normally enough, so this retries rather than sleeping blindly.
  defp await_lastpoint(client, sid, tid, attempts) do
    case TerminalMonitor.lastpoint(client, sid, tid) do
      {:ok, position} when is_tuple(position.location) ->
        position

      other when attempts > 1 ->
        IO.puts("[integration] lastpoint not ready yet (#{inspect(other)}), retrying")
        Process.sleep(1000)
        await_lastpoint(client, sid, tid, attempts - 1)

      other ->
        flunk("lastpoint never reported a position: #{inspect(other)}")
    end
  end

  defp report(label, fun), do: IO.puts("[integration] #{label} -> #{fun.()}")

  defp type_of(nil), do: "nil"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(_other), do: "other"
end
