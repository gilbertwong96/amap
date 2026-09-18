defmodule Amap.Falcon.IntegrationTest do
  @moduledoc """
  Live checks against Amap, for the three facts documentation could not settle:

    1. whether a Falcon POST really accepts `key` in the form body (the upload
       page claims it must be in the URL; every other page lists it as an
       ordinary parameter, and the body path is what the SDK uses);
    2. the real types of `terminal/list`'s `name` and `tid`, whose response table
       contradicts `terminal/add`'s;
    3. whether `lastpoint`'s `"X,Y"` is longitude-first, which is inferred from
       the upload endpoint rather than documented.

  Excluded by default (`test_helper.exs`). Run with a key:

      AMAP_KEY=… mix test --only integration test/amap/falcon/integration_test.exs

  The upload steps call `Amap.request/5` directly because `point/upload` belongs
  to batch S2b; they exist here only to give `lastpoint` something to report.
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

    assert {:ok, service} = Service.add(client, name, desc: "integration test")
    assert is_integer(service.sid)
    sid = service.sid

    on_exit(fn ->
      # Best effort: the terminal may not exist if the test failed early.
      case Terminal.list(client, sid) do
        {:ok, %{items: items}} ->
          Enum.each(items, fn t -> Terminal.delete(client, sid, t.tid) end)

        _other ->
          :ok
      end

      Service.delete(client, sid)
    end)

    # (1) A POST accepted with key in the body: reaching this line proves it.
    assert {:ok, terminal} =
             Terminal.add(client, sid, name, props: %{"kind" => "test"})

    assert is_integer(terminal.tid)
    tid = terminal.tid

    # (2) What list really sends for name and tid, versus its documentation.
    assert {:ok, %Terminal.Page{items: [listed]}} =
             Terminal.list(client, sid)

    assert listed.tid == tid

    IO.puts("""
    [integration] terminal/list types -> tid: #{inspect(listed.tid)} (#{type_of(listed.tid)}), \
    name: #{inspect(listed.name)} (#{type_of(listed.name)}), \
    createtime: #{type_of(listed.createtime)}, locatetime: #{type_of(listed.locatetime)}\
    """)

    assert {:ok, %TerminalSearch.Page{count: count}} =
             TerminalSearch.search(client, sid, name)

    assert count >= 1

    # Give the terminal five points so lastpoint will answer at all.
    assert {:ok, trace} =
             Amap.request(client, :tsapi, :post, "/v1/track/trace/add", sid: sid, tid: tid)

    trid = trace["trid"]

    points =
      for n <- 0..4 do
        %{
          "location" => "#{114.158 + n / 100_000},#{22.279 + n / 100_000}",
          "locatetime" => System.system_time(:millisecond) + n * 1000
        }
      end

    assert {:ok, _} =
             Amap.request(client, :tsapi, :post, "/v1/track/point/upload",
               sid: sid,
               tid: tid,
               trid: trid,
               points: Amap.JSON.encode!(points)
             )

    assert {:ok, position} = TerminalMonitor.lastpoint(client, sid, tid)

    IO.puts("""
    [integration] lastpoint location -> #{inspect(position.location)} \
    (first element #{type_of(elem(position.location, 0))})\
    """)

    # (3) Hong Kong coordinates: a longitude near 114, a latitude near 22. If the
    # parsed tuple is reversed, this assertion is what says so.
    {first, second} = position.location
    assert first > 90, "expected longitude first, got #{inspect(position.location)}"
    assert second < 90, "expected latitude second, got #{inspect(position.location)}"
  end

  defp type_of(nil), do: "nil"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(_other), do: "other"
end
