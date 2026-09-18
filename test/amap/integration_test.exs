defmodule Amap.IntegrationTest do
  @moduledoc """
  Live checks against Amap's Web-service endpoints — the four facts their own pages
  leave open.

  Excluded by default (`test_helper.exs`). Run with a key:

      AMAP_KEY=… mix test --only integration test/amap/integration_test.exs

  What each check is for, and which question its answer settles:

    * `/v3/ip` — that an address Amap cannot place really arrives with its fields as
      empty arrays. This is the behaviour the whole empty-array rule was written
      for, seen once and worth confirming.
    * `/v3/assistant/coordinate/convert` — whether the answer carries `infocode` at
      all, which is the one thing its own page's table leaves out, and that several
      points come back `;`-separated.
    * `/v3/config/district` — how the entries under `districts` are shaped, what an
      omitted `keywords` answers, and where 朝阳区's boundary splits into parts.
    * `/v3/traffic/status/circle` — whether this key has the 高级服务 (premium)
      permission at all. A refusal is reported rather than failed on: it says
      something about the account and nothing about the SDK.
  """

  use ExUnit.Case, async: false

  alias Amap.Convert
  alias Amap.District
  alias Amap.IpLocation
  alias Amap.Traffic

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

  test "IP 定位 answers with empty arrays, not absent fields, for an address it cannot place",
       %{client: client} do
    assert {:ok, own} = IpLocation.ip(client)
    report("ip, caller's own address", fn -> inspect(own) end)

    assert {:ok, foreign} = IpLocation.ip(client, ip: "8.8.8.8")
    report("ip 8.8.8.8", fn -> inspect(foreign) end)

    # Empty arrays reach a caller as nil, which is the rule this endpoint started.
    assert foreign.province == nil
    assert foreign.city == nil
    assert foreign.adcode == nil
  end

  test "坐标转换 answers semicolon-separated points", %{client: client} do
    body =
      raw(client, "/v3/assistant/coordinate/convert",
        locations: "116.481499,39.990475|114.1589,22.2799",
        coordsys: "gps"
      )

    assert {:ok, decoded} = Amap.Response.decode(body)
    report("convert envelope keys", fn -> inspect(Map.keys(decoded)) end)

    assert {:ok, converted} =
             Convert.convert(client, [{116.481499, 39.990475}, {114.1589, 22.2799}],
               coordsys: :gps
             )

    report("convert locations", fn -> inspect(converted.locations) end)
    assert [_, _] = converted.locations
  end

  test "行政区域查询: children, boundaries and an unasked keyword", %{client: client} do
    assert {:ok, beijing} = District.district(client, keywords: "北京", subdistrict: 1)
    assert [%District{} = province] = beijing.items

    report("district 北京", fn ->
      "#{province.name} (#{province.level}), adcode #{inspect(province.adcode)}, " <>
        "children: #{length(province.districts)}"
    end)

    assert province.level == "province"

    assert {:ok, chaoyang} = District.district(client, keywords: "朝阳区", extensions: :all)
    assert [%District{} = district] = chaoyang.items

    report("朝阳区 polyline", fn ->
      case district.polyline do
        nil -> "none"
        parts -> "#{length(parts)} part(s), first with #{length(hd(parts))} points"
      end
    end)

    assert {:ok, nothing} = District.district(client)

    report("district with no keywords", fn ->
      "items: #{length(nothing.items)}, suggestion: " <>
        inspect(nothing.suggestion && nothing.suggestion.keywords)
    end)
  end

  test "交通态势查询 needs 高级服务, so a refusal here is the finding", %{client: client} do
    case Traffic.circle(client, 5, {116.3057764, 39.98641364}, extensions: :all) do
      {:ok, traffic} ->
        report("traffic/status/circle", fn ->
          "#{inspect(traffic.description)}, roads: #{length(traffic.roads)}, " <>
            "evaluation: #{inspect(traffic.evaluation)}"
        end)

        assert is_list(traffic.roads)

      {:error, %Amap.Error{} = error} ->
        report("traffic/status/circle", fn ->
          "refused: #{inspect(error.reason)} (#{inspect(error.code)}) — " <>
            "this key may not have 高级服务 (premium)"
        end)
    end
  end

  # The payload the SDK hands a business module has the envelope already stripped,
  # so a question *about* the envelope is asked of the wire directly.
  defp raw(client, path, params) do
    query =
      params
      |> Keyword.put(:key, client.key)
      |> Amap.Param.encode()
      |> URI.encode_query()

    url = client.base_urls.restapi <> path <> "?" <> query

    body =
      case Finch.request(Finch.build(:get, url), Amap.Finch) do
        {:ok, %Finch.Response{body: body}} -> body
        {:error, reason} -> "request failed: #{inspect(reason)}"
      end

    report("raw #{path}", fn -> body end)
    body
  end

  # One line per finding, prefixed so a run's output reads as a list of answers.
  defp report(label, fun), do: IO.puts("[integration] #{label}: #{fun.()}")
end
