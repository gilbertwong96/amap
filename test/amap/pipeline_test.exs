defmodule Amap.PipelineTest do
  use ExUnit.Case, async: true

  alias Amap.TestServer

  setup do
    server = TestServer.start!()

    client =
      Amap.new(
        key: "test-key",
        base_urls: %{
          restapi: "http://localhost:#{server.port}",
          tsapi: "http://localhost:#{server.port}"
        }
      )

    {:ok, server: server, client: client}
  end

  test "returns the payload for a Web service call", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/ip", fn _req ->
      {200, ~s({"status":"1","info":"OK","infocode":"10000","province":"北京市"})}
    end)

    assert {:ok, %{"province" => "北京市"}} =
             Amap.request(client, :restapi, :get, "/v3/ip", %{})
  end

  test "returns the payload for a Falcon call", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v1/track/service/list", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"services":[]}})}
    end)

    assert {:ok, %{"services" => []}} =
             Amap.request(client, :tsapi, :get, "/v1/track/service/list", %{})
  end

  test "sends to the host the caller names, and parses by the family", %{server: server} do
    # `/v4/direction/bicycling` is a Falcon envelope on the Web service host: it is
    # called as `:tsapi`, which decides the envelope and signing, with
    # `host: :restapi`, which decides where it goes. The tsapi base URL here points
    # at a closed port, so a call that ignored `host:` would fail in transport.
    client =
      Amap.new(
        key: "test-key",
        base_urls: %{restapi: "http://localhost:#{server.port}", tsapi: "http://localhost:1"}
      )

    TestServer.expect_once(server, "GET", "/v4/direction/bicycling", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK","data":{"paths":[]}})}
    end)

    assert {:ok, %{"paths" => []}} =
             Amap.request(client, :tsapi, :get, "/v4/direction/bicycling", %{}, host: :restapi)
  end

  test "returns the payload when Falcon answers with 10000, as the live API does", %{
    server: server,
    client: client
  } do
    # `10000 OK` is the documented success code and what a real call returns; the
    # examples in the docs use 0, so both paths are covered.
    TestServer.expect_once(server, "GET", "/v1/track/service/list", fn _req ->
      {200, ~s({"errcode":10000,"errmsg":"OK","data":{"services":[]}})}
    end)

    assert {:ok, %{"services" => []}} =
             Amap.request(client, :tsapi, :get, "/v1/track/service/list", %{})
  end

  test "surfaces a Falcon error with its detail", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v1/track/terminal/add", fn _req ->
      {200,
       ~s({"errcode":20001,"errmsg":"MISSING_REQUIRED_PARAMS","errdetail":"sid is required"})}
    end)

    assert {:error, error} = Amap.request(client, :tsapi, :get, "/v1/track/terminal/add", %{})
    assert error.reason == :missing_required_params
    assert error.detail == "sid is required"
  end

  test "sends the key and signature on the wire", %{server: server} do
    parent = self()

    TestServer.expect_once(server, "GET", "/v3/geocode/geo", fn req ->
      send(parent, {:query, req.query})

      {200, ~s({"status":"1","info":"OK","infocode":"10000"})}
    end)

    client =
      Amap.new(
        key: "test-key",
        private_key: "priv",
        base_urls: %{
          restapi: "http://localhost:#{server.port}",
          tsapi: "http://localhost:#{server.port}"
        }
      )

    assert {:ok, _} =
             Amap.request(client, :restapi, :get, "/v3/geocode/geo", %{"address" => "beijing"})

    assert_receive {:query, query}
    params = URI.decode_query(query)

    assert params["key"] == "test-key"
    assert params["address"] == "beijing"
    assert params["sig"] == Amap.Signature.sign(Map.to_list(URI.decode_query(query)), "priv")
  end

  test "reports malformed JSON without raising", %{server: server, client: client} do
    TestServer.expect_once(server, "GET", "/v3/ip", fn _req ->
      {200, "<html>gateway</html>"}
    end)

    assert {:error, error} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
    assert error.reason == :invalid_json
  end

  test "waits for the limiter before issuing the request", %{server: server} do
    client =
      Amap.new(
        key: "test-key",
        limiter: [rate: 1, burst: 1],
        base_urls: %{
          restapi: "http://localhost:#{server.port}",
          tsapi: "http://localhost:#{server.port}"
        }
      )

    # `Amap.TestServer.expect_once/4` keeps a single expectation per route and
    # replaces it when called again, it does not queue them. The brief registered
    # it in a `for _ <- 1..2` loop, which armed only one handler: the first
    # request consumed it and the second got a 404 (mapped to
    # `:unexpected_response`). `Amap.TestServer.expect/4` stays armed, so both
    # requests are served.
    TestServer.expect(server, "GET", "/v3/ip", fn _req ->
      {200, ~s({"status":"1","info":"OK","infocode":"10000"})}
    end)

    assert {:ok, _} = Amap.request(client, :restapi, :get, "/v3/ip", %{})

    started = System.monotonic_time(:millisecond)
    assert {:ok, _} = Amap.request(client, :restapi, :get, "/v3/ip", %{})
    assert System.monotonic_time(:millisecond) - started >= 500
  end

  test "routes a limiter timeout through the error struct", %{server: server} do
    base_urls = %{
      restapi: "http://localhost:#{server.port}",
      tsapi: "http://localhost:#{server.port}"
    }

    drain = Amap.new(key: "test-key", limiter: [rate: 1, burst: 1], base_urls: base_urls)

    TestServer.expect(server, "GET", "/v3/ip", fn _req ->
      {200, ~s({"status":"1","info":"OK","infocode":"10000"})}
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
    server: server,
    client: client
  } do
    TestServer.expect_once(server, "GET", "/v1/track/terminal/delete", fn _req ->
      {200, ~s({"errcode":0,"errmsg":"OK"})}
    end)

    assert {:ok, nil} = Amap.request(client, :tsapi, :get, "/v1/track/terminal/delete", %{})
  end

  test "sends a JSON body through the whole pipeline, and retries it", %{
    server: server,
    client: client
  } do
    # 10016 is retryable, so this also proves the body option survives attempt/7
    # rather than being dropped on the way to the retry.
    parent = self()

    TestServer.expect(server, "POST", "/v1/track/match", fn req ->
      send(parent, {:hit, req.headers["content-type"]})
      {200, ~s({"errcode":10016,"errmsg":"SERVER_IS_BUSY"})}
    end)

    retrying = Amap.new(key: "test-key", retry: [max: 1], base_urls: client.base_urls)

    assert {:error, error} =
             Amap.request(retrying, :tsapi, :post, "/v1/track/match", %{"baseline" => %{}},
               body: :json
             )

    assert error.reason == :server_is_busy
    assert_receive {:hit, "application/json"}
    assert_receive {:hit, "application/json"}
    refute_receive {:hit, _content_type}, 50
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
