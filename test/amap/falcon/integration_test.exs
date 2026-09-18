defmodule Amap.Falcon.IntegrationTest do
  @moduledoc """
  Live checks against Amap, for the facts documentation could not settle.

  Excluded by default (`test_helper.exs`). Run with a key:

      AMAP_KEY=… mix test --only integration test/amap/falcon/integration_test.exs

  Established by earlier runs:

    * a Falcon POST is accepted with `key` in the form body;
    * `terminal/list` sends `tid` as an integer and `name` as a string — its own
      response table claims the reverse, and is wrong;
    * Falcon's success code is `10000`, not only `0` (see `Amap.Response`).

  This run prints the raw payload of `trace/add`, `point/upload` and `lastpoint`,
  because a `lastpoint` that succeeds with every field `nil` means the points are
  not where that call looks, and `data.errorpoints` is the only place Amap says
  why. The upload's data is deliberately not asserted away.

  Still open: `lastpoint`'s `"X,Y"` order, inferred from the upload endpoint. The
  assertion compares it against the coordinates this test uploaded, so a reversal
  fails rather than being guessed at.
  """

  use ExUnit.Case, async: false

  alias Amap.Falcon.Grasproad
  alias Amap.Falcon.Point
  alias Amap.Falcon.Service
  alias Amap.Falcon.Terminal
  alias Amap.Falcon.TerminalColumn
  alias Amap.Falcon.TerminalMonitor
  alias Amap.Falcon.TerminalSearch
  alias Amap.Falcon.Trace

  @moduletag :integration
  @moduletag timeout: 60_000

  # .exs files are loaded on every run, so setting AMAP_KEY and re-running is
  # enough; without one the module skips rather than failing.
  if System.get_env("AMAP_KEY") in [nil, ""] do
    @moduletag :skip
  end

  # The first uploaded point, and the frame the lastpoint assertion compares to.
  @first_point {114.158, 22.279}

  setup do
    client = Amap.new(key: System.fetch_env!("AMAP_KEY"))
    {:ok, client: client}
  end

  test "a service, a terminal, a search and a real position", %{client: client} do
    name = "sdk_it_#{System.unique_integer([:positive])}"

    assert {:ok, service} = Service.add(client, name, desc: "集成测试")
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
    tid = terminal.tid

    assert {:ok, %Terminal.Page{items: [listed]}} = Terminal.list(client, sid)
    assert listed.tid == tid

    report("terminal/list", fn ->
      "tid: #{inspect(listed.tid)} (#{type_of(listed.tid)}), " <>
        "name: #{inspect(listed.name)} (#{type_of(listed.name)}), " <>
        "createtime: #{type_of(listed.createtime)}, locatetime: #{type_of(listed.locatetime)}"
    end)

    assert {:ok, %TerminalSearch.Page{} = before_points} =
             TerminalSearch.search(client, sid, name)

    report("search before any position", fn -> "count: #{inspect(before_points.count)}" end)

    # A short but plausible track: five points a second apart, each about 30 m
    # from the last, all in the past.
    {lon0, lat0} = @first_point
    now = System.system_time(:millisecond)

    points =
      for n <- 0..4 do
        %{
          "location" => "#{lon0 + n * 0.0003},#{lat0 + n * 0.0003}",
          "locatetime" => now - (4 - n) * 1000
        }
      end

    {:ok, trace} =
      Amap.request(client, :tsapi, :post, "/v1/track/trace/add", sid: sid, tid: tid)

    report("trace/add", fn -> inspect(trace) end)
    trid = trace["trid"]

    {:ok, uploaded} =
      Amap.request(client, :tsapi, :post, "/v1/track/point/upload",
        sid: sid,
        tid: tid,
        trid: trid,
        points: Amap.JSON.encode!(points)
      )

    report("point/upload", fn -> inspect(uploaded) end)
    report("points sent", fn -> inspect(points) end)
    report("trace id", fn -> inspect(trid) end)

    report("lastpoint raw", fn ->
      inspect(
        Amap.request(client, :tsapi, :get, "/v1/track/terminal/lastpoint", sid: sid, tid: tid)
      )
    end)

    positions =
      for correction <- [:n, nil] do
        # `correction: :n` is documented as "return the last point the user
        # uploaded", which is what a test wants; the default snaps to roads and
        # may drop fields.
        result = TerminalMonitor.lastpoint(client, sid, tid, correction: correction)
        report("lastpoint correction=#{inspect(correction)}", fn -> inspect(result) end)
        {correction, result}
      end

    {_mode, {:ok, position}} =
      Enum.find(positions, fn {_mode, result} ->
        case result do
          {:ok, %{location: location}} -> is_tuple(location)
          _other -> false
        end
      end) || flunk("lastpoint never reported a position: #{inspect(positions)}")

    {first, second} = position.location
    {expected_first, expected_second} = @first_point
    report("lastpoint location", fn -> "#{inspect(position.location)}" end)

    # The coordinates uploaded are longitude 114…, latitude 22…, so the parsed
    # tuple has to come back in the same order. This is the assertion that says
    # whether the endpoint's undocumented "X,Y" is longitude-first.
    assert_in_delta first,
                    expected_first + 0.0012,
                    0.01,
                    "expected longitude #{expected_first} first, got #{inspect(position.location)}"

    assert_in_delta second,
                    expected_second + 0.0012,
                    0.01,
                    "expected latitude #{expected_second} second, got #{inspect(position.location)}"

    assert {:ok, %TerminalSearch.Page{} = after_points} =
             TerminalSearch.search(client, sid, name)

    report("search after a position exists", fn -> "count: #{inspect(after_points.count)}" end)

    assert {:ok, %TerminalSearch.Page{} = around} =
             TerminalSearch.aroundsearch(client, sid, @first_point, radius: 1000)

    report("aroundsearch within 1km", fn -> "count: #{inspect(around.count)}" end)
  end

  test "a custom field, a trajectory and a correction", %{client: client} do
    # This is what S2a's run could not do: `props` is rejected until the field has
    # been declared, and declaring it is what this batch added.
    assert {:ok, nil} =
             TerminalColumn.add(client, service_sid = create_service(client), "plate", :string)

    sid = service_sid

    on_exit(fn ->
      case Terminal.list(client, sid) do
        {:ok, %{items: items}} -> Enum.each(items, &Terminal.delete(client, sid, &1.tid))
        _other -> :ok
      end

      Service.delete(client, sid)
    end)

    assert {:ok, terminal} = Terminal.add(client, sid, "truck", props: %{"plate" => "AB1234"})
    tid = terminal.tid

    assert {:ok, %Terminal.Page{items: [listed]}} = Terminal.list(client, sid)
    report("terminal props round-trip", fn -> inspect(listed.props) end)

    assert {:ok, trace} = Trace.add(client, sid, tid, trname: "morning")
    trid = trace.trid

    now = System.system_time(:millisecond)

    points =
      for n <- 0..4 do
        %{
          location: {114.158 + n * 0.0003, 22.279 + n * 0.0003},
          locatetime: now - (4 - n) * 1000,
          # Outside the documented [0,360], so Amap should refuse this one point
          # while storing the rest — which is what makes errorpoints non-empty.
          direction: if(n == 2, do: 999, else: 120)
        }
      end

    assert {:ok, upload} = Point.upload(client, sid, tid, trid, points)
    report("point/upload errorpoints", fn -> inspect(upload.errorpoints) end)

    assert {:ok, %Grasproad.Result{} = found} = Grasproad.trsearch(client, sid, tid, trid: trid)

    report("trsearch by trid", fn ->
      "counts: #{inspect(found.counts)}, tracks: #{length(found.tracks)}"
    end)

    assert {:ok, %Grasproad.Result{}} =
             Grasproad.trsearch(client, sid, tid,
               starttime: now - 60_000,
               endtime: now,
               correction: [mapmatch: false]
             )

    # Enabled by ticket, so an error here is the expected answer rather than a
    # failure: what matters is that the call is shaped correctly.
    report("roaddata", fn ->
      inspect(Grasproad.roaddata(client, sid: sid, tid: tid, trid: trid))
    end)
  end

  defp create_service(client) do
    name = "sdk_it_#{System.unique_integer([:positive])}"

    assert {:ok, service} = Service.add(client, name, desc: "集成测试")
    service.sid
  end

  defp report(label, fun), do: IO.puts("[integration] #{label} -> #{fun.()}")

  defp type_of(nil), do: "nil"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(_other), do: "other"
end
