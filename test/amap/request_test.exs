defmodule Amap.RequestTest do
  use ExUnit.Case, async: true

  alias Amap.{Client, Request}

  defp client(opts \\ []) do
    struct!(Client, [key: "test-key"] ++ opts)
  end

  describe "build/5" do
    test "targets the family host and path" do
      request =
        Request.build(client(), :restapi, :get, "/v3/geocode/geo", %{"address" => "beijing"})

      assert request.host == "restapi.amap.com"
      assert request.path == "/v3/geocode/geo"
      assert request.scheme == :https
      assert request.method == "GET"
    end

    test "targets the Falcon host for the tsapi family" do
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

    test "adds sig for the Web service family when a private key is configured" do
      request =
        Request.build(client(private_key: "priv"), :restapi, :get, "/v3/ip", %{"a" => "1"})

      expected =
        Amap.Signature.sign([{"key", "test-key"}, {"a", "1"}], "priv")

      assert request.query =~ "sig=#{expected}"
    end

    test "never adds sig for the Falcon family" do
      request =
        Request.build(client(private_key: "priv"), :tsapi, :get, "/v1/track/service/list", %{})

      refute request.query =~ "sig="
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

      raw_sig = Amap.Signature.sign([{"key", "test-key"}, {"keywords", "a b"}], "priv")

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

    test "rejects a reserved parameter on the Falcon family too" do
      # `sig` is never injected for `:tsapi`, but `key` always is, and the guard
      # runs before the family is considered so both are rejected either way.
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
      bypass = Bypass.open()

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
            restapi: "http://localhost:#{bypass.port}",
            tsapi: "http://localhost:#{bypass.port}"
          }
        )

      {:ok, bypass: bypass, client: client}
    end

    test "returns the response on success", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v3/ip", fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s({"status":"1","info":"OK","infocode":"10000"}))
      end)

      assert {:ok, %Finch.Response{status: 200} = response} =
               Request.send(client, :restapi, :get, "/v3/ip", %{})

      assert response.body =~ "OK"
    end

    test "reports a non-200 status as an unexpected response", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/v3/ip", fn conn ->
        Plug.Conn.send_resp(conn, 502, "<html>bad gateway</html>")
      end)

      assert {:error, error} = Request.send(client, :restapi, :get, "/v3/ip", %{})
      assert error.reason == :unexpected_response
      assert error.http_status == 502
    end

    test "reports a connection failure as a transport error", %{bypass: bypass, client: client} do
      Bypass.down(bypass)

      assert {:error, error} = Request.send(client, :restapi, :get, "/v3/ip", %{})
      assert error.reason == :transport
    end
  end
end
