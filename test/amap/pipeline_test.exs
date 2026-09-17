defmodule Amap.PipelineTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()

    client =
      Amap.new(
        key: "test-key",
        base_urls: %{
          restapi: "http://localhost:#{bypass.port}",
          tsapi: "http://localhost:#{bypass.port}"
        }
      )

    {:ok, bypass: bypass, client: client}
  end

  test "returns the payload for a Web service call", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v3/ip", fn conn ->
      Plug.Conn.send_resp(
        conn,
        200,
        ~s({"status":"1","info":"OK","infocode":"10000","province":"北京市"})
      )
    end)

    assert {:ok, %{"province" => "北京市"}} =
             Amap.request(client, :restapi, :get, "/v3/ip", %{})
  end

  test "returns the payload for a Falcon call", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/track/service/list", fn conn ->
      Plug.Conn.send_resp(conn, 200, ~s({"errcode":0,"errmsg":"OK","data":{"services":[]}}))
    end)

    assert {:ok, %{"services" => []}} =
             Amap.request(client, :tsapi, :get, "/v1/track/service/list", %{})
  end

  test "surfaces a Falcon error with its detail", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v1/track/terminal/add", fn conn ->
      Plug.Conn.send_resp(
        conn,
        200,
        ~s({"errcode":20001,"errmsg":"MISSING_REQUIRED_PARAMS","errdetail":"sid is required"})
      )
    end)

    assert {:error, error} = Amap.request(client, :tsapi, :get, "/v1/track/terminal/add", %{})
    assert error.reason == :missing_required_params
    assert error.detail == "sid is required"
  end

  test "sends the key and signature on the wire", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, "GET", "/v3/geocode/geo", fn conn ->
      send(parent, {:query, conn.query_string})

      Plug.Conn.send_resp(conn, 200, ~s({"status":"1","info":"OK","infocode":"10000"}))
    end)

    client =
      Amap.new(
        key: "test-key",
        private_key: "priv",
        base_urls: %{
          restapi: "http://localhost:#{bypass.port}",
          tsapi: "http://localhost:#{bypass.port}"
        }
      )

    assert {:ok, _} =
             Amap.request(client, :restapi, :get, "/v3/geocode/geo", %{"address" => "beijing"})

    assert_receive {:query, query}
    params = URI.decode_query(query)

    assert params["key"] == "test-key"
    assert params["address"] == "beijing"
    assert params["sig"] == Amap.Signature.sign(URI.decode_query(query) |> Map.to_list(), "priv")
  end

  test "reports malformed JSON without raising", %{bypass: bypass, client: client} do
    Bypass.expect_once(bypass, "GET", "/v3/ip", fn conn ->
      Plug.Conn.send_resp(conn, 200, "<html>gateway</html>")
    end)

    assert {:error, error} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
    assert error.reason == :invalid_json
  end

  test "waits for the limiter before issuing the request", %{bypass: bypass} do
    client =
      Amap.new(
        key: "test-key",
        limiter: [rate: 1, burst: 1],
        base_urls: %{
          restapi: "http://localhost:#{bypass.port}",
          tsapi: "http://localhost:#{bypass.port}"
        }
      )

    # `Bypass.expect_once/4` keeps a single expectation per route and replaces it
    # when called again, it does not queue them. The brief registered it in a
    # `for _ <- 1..2` loop, which armed only one handler: the first request
    # consumed it and the second got a 404 (mapped to `:unexpected_response`).
    # `Bypass.expect/4` stays armed, so both requests are served.
    Bypass.expect(bypass, "GET", "/v3/ip", fn conn ->
      Plug.Conn.send_resp(conn, 200, ~s({"status":"1","info":"OK","infocode":"10000"}))
    end)

    assert {:ok, _} = Amap.request(client, :restapi, :get, "/v3/ip", %{})

    started = System.monotonic_time(:millisecond)
    assert {:ok, _} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
    assert System.monotonic_time(:millisecond) - started >= 500
  end

  test "routes a limiter timeout through the error struct", %{bypass: bypass} do
    base_urls = %{
      restapi: "http://localhost:#{bypass.port}",
      tsapi: "http://localhost:#{bypass.port}"
    }

    drain = Amap.new(key: "test-key", limiter: [rate: 1, burst: 1], base_urls: base_urls)

    Bypass.expect(bypass, "GET", "/v3/ip", fn conn ->
      Plug.Conn.send_resp(conn, 200, ~s({"status":"1","info":"OK","infocode":"10000"}))
    end)

    # The one token in the bucket goes here.
    assert {:ok, _} = Amap.request(drain, :restapi, :get, "/v3/ip", %{})

    # Same bucket, but a budget too small to reach the next token (~1000ms away at
    # 1/s), and URLs pointing at a refused port. Were the limiter not consulted
    # before the request, this would fail as `:transport` rather than
    # `:limiter_timeout`. `timeout` is Finch's receive timeout too, which is
    # harmless here for the same reason: no HTTP is attempted.
    starved =
      Amap.new(
        key: "test-key",
        limiter: drain.limiter,
        timeout: 10,
        base_urls: %{restapi: "http://127.0.0.1:1", tsapi: "http://127.0.0.1:1"}
      )

    # Matching the struct is the point. `Amap.Limiter.acquire/2` speaks a bare
    # `{:error, :timeout}` atom, and `Amap.Telemetry.stop_meta/1` has no catch-all
    # clause to absorb it, so an unwrapped atom would raise from inside the
    # telemetry wrapper instead of surfacing as a rate-limit error.
    assert {:error, %Amap.Error{reason: :limiter_timeout} = error} =
             Amap.request(starved, :restapi, :get, "/v3/ip", %{})

    assert error.retry == :no
  end

  test "returns an empty payload for a Falcon call with no data body", %{
    bypass: bypass,
    client: client
  } do
    Bypass.expect_once(bypass, "GET", "/v1/track/terminal/delete", fn conn ->
      Plug.Conn.send_resp(conn, 200, ~s({"errcode":0,"errmsg":"OK"}))
    end)

    assert {:ok, nil} = Amap.request(client, :tsapi, :get, "/v1/track/terminal/delete", %{})
  end

  test "names an invalid family instead of failing on the URL", %{client: client} do
    error =
      assert_raise ArgumentError, fn ->
        Amap.request(client, :typo, :get, "/v3/ip", %{})
      end

    assert error.message =~ "invalid family: :typo"
    assert error.message =~ ":restapi or :tsapi"
  end
end
