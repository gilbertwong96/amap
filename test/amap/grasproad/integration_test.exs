defmodule Amap.Grasproad.IntegrationTest do
  @moduledoc """
  Live checks for the S3a batch — `/v4/grasproad/driving`, the JSON array body, and the
  shapes the page leaves open.

  Excluded by default (`test_helper.exs`). Run with a key:

      AMAP_KEY=… mix test --only integration test/amap/grasproad/integration_test.exs

  Each check asserts the shape its module promises — a `%Amap.Grasproad.Result{}`, a
  `%Amap.Grasproad.Point{}` inside it, or an `%Amap.Error{}` — and prints the answer with
  `report/2` rather than failing on it: the page never states the success `errcode` and
  types none of the three response scalars, so a hypothesis that turns out wrong is a
  finding rather than a regression. The findings are recorded with the run that made
  them and, where they concern the endpoint's shape, with the other host differences.
  """

  use ExUnit.Case, async: false

  alias Amap.Error
  alias Amap.Grasproad
  alias Amap.Grasproad.Point
  alias Amap.Grasproad.Result
  alias Amap.Param
  alias Amap.Response

  @moduletag :integration
  @moduletag timeout: 60_000

  # .exs files are loaded on every run, so setting AMAP_KEY and re-running is enough;
  # without one the module skips rather than failing.
  if System.get_env("AMAP_KEY") in [nil, ""] do
    @moduletag :skip
  end

  @path "/v4/grasproad/driving"

  # The page's own sample body, in the SDK's point-map shape. The first `tm` is the
  # absolute instant and the rest are seconds from it, exactly as the page defines.
  @page_sample [
    %{location: {116.478928, 39.997761}, ag: 0, tm: 1_478_031_031, sp: 19},
    %{location: {116.478907, 39.998422}, ag: 0, tm: 2, sp: 10},
    %{location: {116.479384, 39.998546}, ag: 110, tm: 3, sp: 10},
    %{location: {116.481053, 39.998204}, ag: 120, tm: 4, sp: 10},
    %{location: {116.481793, 39.997868}, ag: 120, tm: 5, sp: 10},
    %{location: {116.482898, 39.998217}, ag: 30, tm: 6, sp: 10},
    %{location: {116.483789, 39.999063}, ag: 30, tm: 7, sp: 10},
    %{location: {116.484674, 39.999844}, ag: 30, tm: 8, sp: 10}
  ]

  # Two points minutes apart in time and kilometres apart in space — the page says a
  # correction 可能会失败 when the points are 较少或较稀疏, and if anything is refused,
  # this is the track that should be.
  @sparse [
    %{location: {116.397428, 39.90923}, ag: 90, tm: 1_478_031_031, sp: 0},
    %{location: {116.484674, 39.999844}, ag: 90, tm: 300, sp: 0}
  ]

  setup do
    client = Amap.new(key: System.fetch_env!("AMAP_KEY"))
    {:ok, client: client}
  end

  describe "1. the mapped success answer" do
    test "the page's sample track snaps to a Result of Point structs", %{client: client} do
      result = Grasproad.driving(client, @page_sample)
      report("grasproad mapped", fn -> summary(result) end)
      accept!(result, &is_struct(&1, Result))

      case result do
        {:ok, %Result{} = result} ->
          report("grasproad point count against the request", fn ->
            "#{length(result.points)} returned for #{length(@page_sample)} sent"
          end)

          report("grasproad first returned point", fn ->
            inspect(List.first(result.points))
          end)

          report("grasproad mapped point fields", fn ->
            "#{Enum.count(result.points, &is_struct(&1, Point))}/#{length(result.points)} " <>
              "Point structs"
          end)

        _refusal ->
          :ok
      end
    end
  end

  describe "2. the raw success envelope" do
    test "the page gives no success code and no errmsg/errdetail meanings", %{client: client} do
      raw = raw_post(client, @page_sample)

      case Response.decode(raw) do
        {:ok, decoded} when is_map(decoded) ->
          report("grasproad envelope keys", fn -> inspect(Enum.sort(Map.keys(decoded))) end)

          report("grasproad errcode", fn ->
            "#{inspect(decoded["errcode"])} (#{type_of(decoded["errcode"])})"
          end)

          report("grasproad errmsg", fn ->
            "#{inspect(decoded["errmsg"])} (#{type_of(decoded["errmsg"])})"
          end)

          report("grasproad errdetail", fn ->
            "#{inspect(decoded["errdetail"])} (#{type_of(decoded["errdetail"])})"
          end)

          report("grasproad data shape", fn -> data_shape(decoded["data"]) end)
          report("grasproad distance", fn -> distance_shape(decoded["data"]) end)
          report("grasproad points shape", fn -> points_shape(decoded["data"]) end)
          report("grasproad first raw point", fn -> first_raw_point(decoded["data"]) end)

        {:ok, other} ->
          report("grasproad envelope", fn -> "not an object: #{inspect(other)}" end)

        {:error, body} ->
          report("grasproad envelope", fn -> "not JSON: #{String.slice(body, 0, 200)}" end)
      end
    end
  end

  describe "3. a short or sparse track's refusal" do
    test "errcode/errmsg/errdetail when 抓路失败 is what the page says they mean", %{client: client} do
      raw = raw_post(client, @sparse)

      case Response.decode(raw) do
        {:ok, decoded} when is_map(decoded) ->
          report("grasproad sparse errcode", fn ->
            "#{inspect(decoded["errcode"])} (#{type_of(decoded["errcode"])})"
          end)

          report("grasproad sparse errmsg/errdetail", fn ->
            "#{inspect(decoded["errmsg"])} / #{inspect(decoded["errdetail"])}"
          end)

          report("grasproad sparse data", fn -> data_shape(decoded["data"]) end)

        _other ->
          report("grasproad sparse envelope", fn -> "not a decoded object" end)
      end

      result = Grasproad.driving(client, @sparse)
      report("grasproad sparse mapped", fn -> summary(result) end)
      accept!(result, &is_struct(&1, Result))
    end
  end

  describe "4. a one-point track, which cannot be 稀疏" do
    test "what the wire does with a single point", %{client: client} do
      raw = raw_post(client, [hd(@page_sample)])

      case Response.decode(raw) do
        {:ok, decoded} when is_map(decoded) ->
          report("grasproad one-point errcode", fn ->
            "#{inspect(decoded["errcode"])} (#{type_of(decoded["errcode"])})"
          end)

          report("grasproad one-point errmsg/errdetail", fn ->
            "#{inspect(decoded["errmsg"])} / #{inspect(decoded["errdetail"])}"
          end)

          report("grasproad one-point data", fn -> points_shape(decoded["data"]) end)

        _other ->
          report("grasproad one-point envelope", fn -> "not a decoded object" end)
      end
    end
  end

  describe "5. the page's 500-object bound, over the wire" do
    test "501 objects, past the SDK's own refusal", %{client: client} do
      raw = raw_post(client, List.duplicate(hd(@page_sample), 501))

      case Response.decode(raw) do
        {:ok, decoded} when is_map(decoded) ->
          report("grasproad 501 errcode", fn ->
            "#{inspect(decoded["errcode"])} (#{type_of(decoded["errcode"])})"
          end)

          report("grasproad 501 errmsg/errdetail", fn ->
            "#{inspect(decoded["errmsg"])} / #{inspect(decoded["errdetail"])}"
          end)

          report("grasproad 501 data", fn -> data_shape(decoded["data"]) end)

        _other ->
          report("grasproad 501 envelope", fn -> "not a decoded object" end)
      end
    end
  end

  describe "6. an empty array" do
    test "what the wire does with no points at all", %{client: client} do
      raw = raw_post(client, [])

      case Response.decode(raw) do
        {:ok, decoded} when is_map(decoded) ->
          report("grasproad empty errcode", fn ->
            "#{inspect(decoded["errcode"])} (#{type_of(decoded["errcode"])})"
          end)

          report("grasproad empty errmsg/errdetail", fn ->
            "#{inspect(decoded["errmsg"])} / #{inspect(decoded["errdetail"])}"
          end)

        _other ->
          report("grasproad empty envelope", fn -> "not a decoded object" end)
      end
    end
  end

  # The payload a business module sees has the envelope already stripped, so a question
  # about the raw body is asked of the wire with Finch directly. The key goes in the
  # query string, which is where the page's 1.1 puts it, and the body is the JSON array
  # the SDK's own call sends — the two facts this probe is here to confirm.
  defp raw_post(client, points) do
    body = JSON.encode!(Enum.map(points, &wire_point/1))
    url = client.base_urls.restapi <> @path <> "?" <> URI.encode_query(key: client.key)

    request = Finch.build(:post, url, [{"content-type", "application/json"}], body)

    case Finch.request(request, client.pool) do
      {:ok, %Finch.Response{status: status, body: response_body}} ->
        report("raw POST #{@path}", fn ->
          "HTTP #{status}, #{byte_size(body)} request bytes, #{byte_size(response_body)} response bytes"
        end)

        response_body

      {:error, reason} ->
        flunk("raw POST #{@path} failed: #{inspect(reason)}")
    end
  end

  defp wire_point(point) do
    {lon, lat} = point.location

    %{
      "x" => coord(lon),
      "y" => coord(lat),
      "ag" => point.ag,
      "tm" => point.tm,
      "sp" => point.sp
    }
  end

  defp coord(value) when is_integer(value), do: value
  defp coord(value) when is_float(value), do: value |> Param.coord() |> Float.parse() |> elem(0)

  defp data_shape(data) when is_map(data), do: "map; keys: #{inspect(Enum.sort(Map.keys(data)))}"
  defp data_shape(data) when is_list(data), do: "list of #{length(data)}"
  defp data_shape(nil), do: "absent"
  defp data_shape(other), do: type_of(other)

  defp distance_shape(data) when is_map(data) do
    value = data["distance"]
    "#{inspect(value)} (#{type_of(value)})"
  end

  defp distance_shape(_other), do: "no data object"

  defp points_shape(data) when is_map(data) do
    case data["points"] do
      points when is_list(points) ->
        "#{length(points)} point(s); first: #{inspect(List.first(points))}"

      other ->
        "points: #{type_of(other)}"
    end
  end

  defp points_shape(_other), do: "no data object"

  defp first_raw_point(data) when is_map(data) do
    case data["points"] do
      [point | _] when is_map(point) -> inspect(point)
      [other | _] -> "first entry is #{type_of(other)}"
      _empty_or_absent -> "no points"
    end
  end

  defp first_raw_point(_other), do: "no data object"

  # The two shapes every public function here promises: the struct it maps, or an
  # `Amap.Error` for what Amap refused. A refusal is an answer for these checks, so it
  # is reported rather than failed on; anything else is a bug and flunks.
  defp accept!(result, predicate) do
    case result do
      {:ok, value} ->
        assert predicate.(value), "expected the promised shape, got: #{inspect(value)}"

      {:error, %Error{}} ->
        :ok

      other ->
        flunk("expected {:ok, _} or {:error, %Amap.Error{}}, got: #{inspect(other)}")
    end
  end

  defp summary({:ok, %Result{} = result}) do
    "#{length(result.points)} point(s), distance=#{inspect(result.distance)} " <>
      "(#{type_of(result.distance)}); first: #{inspect(List.first(result.points))}"
  end

  defp summary({:error, %Error{reason: reason, code: code, message: message, detail: detail}}) do
    "refused: reason=#{inspect(reason)} code=#{inspect(code)} message=#{inspect(message)} " <>
      "detail=#{inspect(detail)}"
  end

  defp summary(other), do: inspect(other)

  defp type_of(nil), do: "nil"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(value) when is_list(value), do: "list"
  defp type_of(value) when is_map(value), do: "map"
  defp type_of(_other), do: "other"

  # One line per finding, prefixed so a run's output reads as a list of answers.
  defp report(label, fun), do: IO.puts("[integration] #{label}: #{fun.()}")
end
