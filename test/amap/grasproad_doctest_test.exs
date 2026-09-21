defmodule Amap.GrasproadDoctestTest do
  use ExUnit.Case, async: false

  alias Amap.TestServer

  # Falcon success, `data` as `{distance, points[]}` with numbers.
  @corrected ~s({"errcode":0,"errmsg":"OK","data":{"distance":696.0,) <>
               ~s("points":[{"x":116.478928,"y":39.997761},) <>
               ~s({"x":116.47893,"y":39.9978},) <>
               ~s({"x":116.479384,"y":39.998546}]}})

  # 30001 抓路失败: what the run saw for tracks too thin to snap.
  @failed ~s({"errcode":30001,"errmsg":"ENGINE_RESPONSE_DATA_ERROR",) <>
            ~s("errdetail":"引擎返回数据异常"})

  setup_all do
    server = TestServer.start_doctest!()

    TestServer.expect(server, "POST", "/v4/grasproad/driving", fn request ->
      case JSON.decode!(request.body) do
        [_one_point] -> {200, @failed}
        _track -> {200, @corrected}
      end
    end)

    :ok
  end

  doctest Amap.Grasproad
end
