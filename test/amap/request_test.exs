defmodule Amap.RequestTest do
  use ExUnit.Case, async: true

  alias Amap.Signature
  alias Amap.TestServer

  alias Amap.{Client, Host, Request}

  defp client(opts \\ []) do
    struct!(Client, [key: "test-key"] ++ opts)
  end

  describe "build/5" do
    test "targets the :restapi host and path" do
      request =
        Request.build(client(), :restapi, :get, "/v3/geocode/geo", %{"address" => "beijing"})

      assert request.host == "restapi.amap.com"
      assert request.path == "/v3/geocode/geo"
      assert request.scheme == :https
      assert request.method == "GET"
    end

    test "targets the Falcon host for a :tsapi call" do
      request = Request.build(client(), :tsapi, :post, "/v1/track/service/list", %{})

      assert request.host == "tsapi.amap.com"
      assert request.method == "POST"
    end

    test "always injects the key" do
      request = Request.build(client(key: "abc"), :restapi, :get, "/v3/ip", %{})

      assert request.query =~ "key=abc"
    end

    test "omits sig when no private key is configured" do
      request = Request.build(client(), :restapi, :get, "/v3/ip", %{})

      refute request.query =~ "sig="
    end

    test "adds sig for the :restapi envelope when a private key is configured" do
      request =
        Request.build(client(private_key: "priv"), :restapi, :get, "/v3/ip", %{"a" => "1"})

      expected =
        Signature.sign([{"key", "test-key"}, {"a", "1"}], "priv")

      assert request.query =~ "sig=#{expected}"
    end

    test "never adds sig for the :tsapi envelope" do
      request =
        Request.build(client(private_key: "priv"), :tsapi, :get, "/v1/track/service/list", %{})

      refute request.query =~ "sig="
    end

    test "sends a /v4/ call to the host and envelope it names" do
      request =
        Request.build(client(private_key: "priv"), :restapi, :get, "/v4/direction/bicycling", %{},
          envelope: :tsapi
        )

      assert request.host == "restapi.amap.com"
      refute request.query =~ "sig="
    end

    test "refuses an envelope the host does not answer" do
      error =
        assert_raise ArgumentError, fn ->
          Request.build(client(private_key: "priv"), :tsapi, :get, "/v3/ip", %{},
            envelope: :restapi
          )
        end

      assert error.message =~ "invalid envelope: :restapi for the :tsapi host"
    end

    test "sends each host to its own base URL" do
      custom = client(base_urls: %{restapi: "http://rest", tsapi: "http://track"})

      assert Request.build(custom, :restapi, :get, "/v3/ip", %{}).host == "rest"
      assert Request.build(custom, :tsapi, :get, "/v3/ip", %{}).host == "track"
    end

    test "rejects a host it does not describe" do
      error =
        assert_raise ArgumentError, fn ->
          Request.build(client(), :bogus, :get, "/v3/ip", %{})
        end

      assert error.message =~ "invalid host: :bogus"
      assert error.message =~ ":restapi"
      assert error.message =~ ":apilocate"
    end

    test "rejects the removed :host option instead of ignoring it" do
      # The old shape named the host in the options; ignoring it now would send the
      # call to the positional host while the caller believed the option won.
      error =
        assert_raise ArgumentError, fn ->
          Request.build(client(), :tsapi, :get, "/v4/direction/bicycling", %{}, host: :restapi)
        end

      assert error.message =~ ":host option was removed"
      assert error.message =~ "second argument"
    end

    test "rejects an option it does not take, naming it" do
      error =
        assert_raise ArgumentError, fn ->
          Request.build(client(), :restapi, :get, "/v3/ip", %{}, envelop: :tsapi)
        end

      assert error.message =~ "unknown option(s): [:envelop]"
      assert error.message =~ "[:envelope, :body]"
    end

    test "puts a JSON body on the host and envelope the caller names" do
      request =
        Request.build(client(), :restapi, :post, "/v1/track/match", %{"a" => 1},
          body: :json,
          envelope: :tsapi
        )

      assert request.host == "restapi.amap.com"
    end

    test "accepts a list of maps as a JSON body, which one endpoint sends as an array" do
      request =
        Request.build(
          client(),
          :restapi,
          :post,
          "/v4/grasproad/driving",
          [%{"x" => 116.478928, "y" => 39.997761}],
          body: :json,
          envelope: :tsapi
        )

      assert request.host == "restapi.amap.com"
      assert request.method == "POST"
      assert {"content-type", "application/json"} in request.headers
      assert JSON.decode!(request.body) == [%{"x" => 116.478928, "y" => 39.997761}]
    end

    test "describes the et-api host, and refuses to build its digest auth" do
      # `clientKey` + `timestamp` + `digest` is the whole auth on that host, and
      # the digest algorithm is not public, so the request path can state the
      # shape but cannot send it.
      assert Host.describe(:et_api).key_param == "clientKey"

      error =
        assert_raise ArgumentError, fn ->
          Request.build(client(), :et_api, :get, "/event/queryByAdcode", %{})
        end

      assert error.message =~ "cannot build a request for the :et_api host"
      assert error.message =~ "clientKey + timestamp + digest"
    end

    test "sends to apilocate with its own key name and no signature" do
      request =
        Request.build(client(key: "abc", private_key: "priv"), :apilocate, :get, "/position", %{
          "imei" => "1"
        })

      assert request.host == "apilocate.amap.com"
      assert request.query =~ "key=abc"
      refute request.query =~ "sig="
    end

    test "refuses a JSON body that is neither an object nor a non-empty list of objects" do
      for payload <- ["text", 123, [], [1, 2], [%{"a" => 1}, "b"], [["nested"]]] do
        assert_raise ArgumentError,
                     ~r/a JSON body must be a map or a non-empty list of maps/,
                     fn ->
                       Request.build(client(), :tsapi, :post, "/v4/grasproad/driving", payload,
                         body: :json
                       )
                     end
      end
    end

    test "url-encodes values only after signing" do
      request =
        Request.build(
          client(private_key: "priv"),
          :restapi,
          :get,
          "/v3/place/text",
          %{"keywords" => "a b"}
        )

      raw_sig = Signature.sign([{"key", "test-key"}, {"keywords", "a b"}], "priv")

      assert request.query =~ "sig=#{raw_sig}"
      assert request.query =~ "keywords=a+b"
    end

    test "sends parameters as a form body on POST" do
      request =
        Request.build(client(), :tsapi, :post, "/v1/track/terminal/add", %{"name" => "car"})

      assert request.body =~ "key=test-key"
      assert request.body =~ "name=car"
      assert {"content-type", "application/x-www-form-urlencoded"} in request.headers
    end

    test "does not put parameters in the query on POST" do
      request =
        Request.build(client(), :tsapi, :post, "/v1/track/terminal/add", %{"name" => "car"})

      # Finch types `query` as `String.t() | nil` and leaves it nil when the
      # request has no query string, so coerce before matching.
      refute (request.query || "") =~ "name=car"
    end

    test "rejects a caller-supplied key instead of sending two of them" do
      # The client injects `key` itself. Before this guard the injection used an
      # atom key while `Param.encode/1` produces string keys, so a caller's
      # `"key"` was not replaced but joined: the wire carried two `key` values
      # and server-side parsing kept the caller's.
      assert_raise ArgumentError, ~r/request parameter "key"/, fn ->
        Request.build(client(), :restapi, :get, "/v3/ip", %{"key" => "user-key"})
      end
    end

    test "rejects a caller-supplied sig" do
      assert_raise ArgumentError, ~r/request parameter "sig"/, fn ->
        Request.build(
          client(private_key: "priv"),
          :restapi,
          :get,
          "/v3/ip",
          %{"sig" => "user-sig"}
        )
      end
    end

    test "rejects a reserved parameter on the Falcon host too" do
      # `sig` is never injected for `:tsapi`, but `key` always is, and the guard
      # runs before the host is resolved so both are rejected either way.
      assert_raise ArgumentError, ~r/request parameter "key"/, fn ->
        Request.build(client(), :tsapi, :post, "/v1/track/service/list", %{"key" => "user-key"})
      end
    end

    test "still accepts a parameter that merely resembles a reserved name" do
      # Guards against a substring check, which would reject `keys` and `sign`.
      request =
        Request.build(client(), :restapi, :get, "/v3/ip", %{"keys" => "1", "sign" => "2"})

      assert request.query =~ "keys=1"
      assert request.query =~ "sign=2"
      assert request.query =~ "key=test-key"
    end
  end

  describe "send/5" do
    setup do
      server = TestServer.start!()

      # These are unit tests for Request, so they provide their own pool rather
      # than depending on `Amap.Finch`, which the application tree only starts
      # in Task 11. Calling Finch with an unstarted name raises
      # `ArgumentError: unknown registry`.
      pool = :"finch_#{System.unique_integer([:positive])}"
      start_supervised!({Finch, name: pool})

      client =
        client(
          pool: pool,
          base_urls: %{
            restapi: "http://localhost:#{server.port}",
            tsapi: "http://localhost:#{server.port}"
          }
        )

      {:ok, server: server, client: client}
    end

    test "returns the response on success", %{server: server, client: client} do
      TestServer.expect_once(server, "GET", "/v3/ip", fn _req ->
        {200, ~s({"status":"1","info":"OK","infocode":"10000"})}
      end)

      assert {:ok, %Finch.Response{status: 200} = response} =
               Request.send(client, :restapi, :get, "/v3/ip", %{})

      assert response.body =~ "OK"
    end

    test "reports a non-200 status as an unexpected response", %{server: server, client: client} do
      TestServer.expect_once(server, "GET", "/v3/ip", fn _req ->
        {502, "<html>bad gateway</html>"}
      end)

      assert {:error, error} = Request.send(client, :restapi, :get, "/v3/ip", %{})
      assert error.reason == :unexpected_response
      assert error.http_status == 502
    end

    test "reports a connection failure as a transport error", %{server: server, client: client} do
      TestServer.down(server)

      assert {:error, error} = Request.send(client, :restapi, :get, "/v3/ip", %{})
      assert error.reason == :transport
    end

    test "sends a JSON body when asked, keeping the map's shape", %{
      server: server,
      client: client
    } do
      parent = self()

      TestServer.expect_once(server, "POST", "/v1/track/match", fn req ->
        send(parent, {:body, req.headers["content-type"], req.body, req.query})
        {200, ~s({"errcode":10000,"errmsg":"OK","data":{}})}
      end)

      assert {:ok, %Finch.Response{status: 200}} =
               Request.send(
                 client,
                 :tsapi,
                 :post,
                 "/v1/track/match",
                 %{
                   "baseline" => %{"sid" => 1, "tid" => 2, "trid" => 3},
                   "isPoints" => 1
                 },
                 body: :json
               )

      assert_receive {:body, "application/json", body, query}

      # The key travels in the query string as well: a live call with it only in the
      # body answered 10001 INVALID_USER_KEY, so this service does not read it there.
      assert URI.decode_query(query) == %{"key" => "test-key"}

      # Nested objects stay nested: `Param.encode/1` would flatten them into string
      # pairs, which is why the JSON path does not go through it.
      assert JSON.decode!(body) == %{
               "key" => "test-key",
               "baseline" => %{"sid" => 1, "tid" => 2, "trid" => 3},
               "isPoints" => 1
             }
    end

    test "sends a JSON array body when asked", %{server: server, client: client} do
      parent = self()

      TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn req ->
        send(parent, {:body, req.headers["content-type"], req.body, req.query})
        {200, ~s({"errcode":0,"errmsg":"OK","data":{}})}
      end)

      assert {:ok, %Finch.Response{status: 200}} =
               Request.send(
                 client,
                 :restapi,
                 :post,
                 "/v4/grasproad/driving",
                 [%{"x" => 116.478928, "y" => 39.997761}, %{"x" => 116.478907}],
                 body: :json,
                 envelope: :tsapi
               )

      assert_receive {:body, "application/json", body, query}
      assert URI.decode_query(query) == %{"key" => "test-key"}

      assert JSON.decode!(body) == [
               %{"x" => 116.478928, "y" => 39.997761},
               %{"x" => 116.478907}
             ]
    end

    test "keeps the request context for a failed array-body call", %{
      server: server,
      client: client
    } do
      TestServer.expect_once(server, "POST", "/v4/grasproad/driving", fn _req ->
        {502, "<html>bad gateway</html>"}
      end)

      assert {:error, error} =
               Request.send(
                 client,
                 :restapi,
                 :post,
                 "/v4/grasproad/driving",
                 [%{"x" => 116.478928}],
                 body: :json,
                 envelope: :tsapi
               )

      assert error.request.method == :post
      assert error.request.path == "/v4/grasproad/driving"
      assert error.request.params == [%{"x" => 116.478928}]
    end

    test "a JSON body reserves the same parameter names as a form", %{client: client} do
      assert_raise ArgumentError, ~r/invalid request parameter "key"/, fn ->
        Request.build(client, :tsapi, :post, "/v1/track/match", %{"key" => "mine"}, body: :json)
      end
    end

    test "refuses a JSON body where the request would be signed", %{client: client} do
      error =
        assert_raise ArgumentError, fn ->
          Request.build(client, :restapi, :post, "/v3/ip", %{}, body: :json)
        end

      assert error.message =~ "a JSON body is only supported where the request is not signed"
    end

    test "rejects a body encoding Amap does not take", %{client: client} do
      assert_raise ArgumentError, ~r/:body must be :form or :json, got: :xml/, fn ->
        Request.build(client, :tsapi, :post, "/v1/track/match", %{}, body: :xml)
      end
    end
  end
end
