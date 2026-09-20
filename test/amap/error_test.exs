defmodule Amap.ErrorTest do
  use ExUnit.Case, async: true

  alias Amap.Error

  @restapi_body %{"status" => "0", "info" => "INVALID_USER_KEY", "infocode" => "10001"}
  @tsapi_body %{
    "errcode" => 10001,
    "errmsg" => "INVALID_USER_KEY",
    "errdetail" => "key abc is expired"
  }

  describe "from_restapi/2" do
    test "reads info and infocode" do
      error = Error.from_restapi(@restapi_body, 200)

      assert error.code == 10001
      assert error.message == "INVALID_USER_KEY"
      assert error.reason == :invalid_key
      assert error.family == :restapi
      assert error.http_status == 200
      assert error.detail == nil
      assert error.retry == :no
    end

    test "keeps the raw envelope" do
      error = Error.from_restapi(@restapi_body, 200)

      assert error.raw == @restapi_body
    end
  end

  describe "from_tsapi/2" do
    test "reads errmsg and errdetail" do
      error = Error.from_tsapi(@tsapi_body, 200)

      assert error.code == 10001
      assert error.message == "INVALID_USER_KEY"
      assert error.detail == "key abc is expired"
      assert error.reason == :invalid_key
      assert error.family == :tsapi
    end

    test "accepts a string errcode" do
      error = Error.from_tsapi(%{"errcode" => "10001", "errmsg" => "x"}, 200)

      assert error.code == 10001
    end

    test "classifies quota failures for backoff with a wait window" do
      body = %{"errcode" => 10004, "errmsg" => "ACCESS_TOO_FREQUENT"}
      error = Error.from_tsapi(body, 200)

      assert error.reason == :access_too_frequent
      assert error.retry == :backoff
      assert error.retry_after == 60_000
    end

    test "classifies transient failures for immediate retry" do
      body = %{"errcode" => 10016, "errmsg" => "SERVER_IS_BUSY"}

      assert Error.from_tsapi(body, 200).retry == :immediate
    end
  end

  describe "client-side failures" do
    test "wraps a transport error" do
      error = Error.from_transport(%Mint.TransportError{reason: :econnrefused})

      assert error.reason == :transport
      assert error.code == nil
      assert error.retry == :immediate
      assert %Mint.TransportError{} = error.response.exception
    end

    test "wraps malformed JSON" do
      error = Error.invalid_json(200, "<html>gateway</html>")

      assert error.reason == :invalid_json
      assert error.response.body == "<html>gateway</html>"
      assert error.retry == :immediate
    end

    test "wraps an envelope that matches neither family" do
      error = Error.unexpected_response(200, %{"weird" => true})

      assert error.reason == :unexpected_response
      assert error.retry == :no
    end

    test "wraps a limiter timeout" do
      error = Error.limiter_timeout()

      assert error.reason == :limiter_timeout
      assert error.retry == :no
    end
  end

  describe "mask/1" do
    test "redacts credentials" do
      masked = Error.mask(key: "secret-key", sid: 42, sig: "abc")

      assert masked["key"] == "[FILTERED]"
      assert masked["sig"] == "[FILTERED]"
      assert masked["sid"] == 42
    end

    test "redacts the private key" do
      assert Error.mask(private_key: "topsecret")["private_key"] == "[FILTERED]"
    end

    test "does not redact unrelated parameters" do
      assert Error.mask(address: "beijing") == %{"address" => "beijing"}
    end

    test "masks every map of a JSON array body" do
      assert Error.mask([%{key: "secret", x: 1}, %{"sig" => "abc", "y" => 2}]) ==
               [%{"key" => "[FILTERED]", "x" => 1}, %{"sig" => "[FILTERED]", "y" => 2}]
    end
  end

  describe "attach_request/4" do
    test "records the method and path with masked parameters" do
      error =
        %{"status" => "0", "info" => "INVALID_USER_KEY", "infocode" => "10001"}
        |> Error.from_restapi(200)
        |> Error.attach_request(:get, "/v3/geocode/geo", key: "secret", address: "beijing")

      assert error.request.method == :get
      assert error.request.path == "/v3/geocode/geo"
      assert error.request.params["key"] == "[FILTERED]"
      assert error.request.params["address"] == "beijing"
    end
  end
end
