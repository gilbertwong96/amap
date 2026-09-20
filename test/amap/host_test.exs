defmodule Amap.HostTest do
  use ExUnit.Case, async: true

  alias Amap.Host

  describe "names/0 and default_base_urls/0" do
    test "every host the evidence names is described" do
      assert :restapi in Host.names()
      assert :tsapi in Host.names()
      assert :et_api in Host.names()
      assert :apilocate in Host.names()
    end

    test "each host states its origin" do
      assert Host.default_base_urls() == %{
               restapi: "https://restapi.amap.com",
               tsapi: "https://tsapi.amap.com",
               et_api: "https://et-api.amap.com",
               apilocate: "https://apilocate.amap.com"
             }
    end
  end

  describe "describe/2" do
    test "the Web service host answers the flat envelope, signed" do
      host = Host.describe(:restapi)

      assert host.name == :restapi
      assert host.base_url == "https://restapi.amap.com"
      assert host.envelope == :restapi
      assert host.auth == :signature
      assert host.key_param == "key"
    end

    test "the Falcon host answers the errcode envelope, key only" do
      host = Host.describe(:tsapi)

      assert host.base_url == "https://tsapi.amap.com"
      assert host.envelope == :tsapi
      assert host.auth == :key_only
      assert host.key_param == "key"
    end

    test "the Web service host answers the errcode envelope too, without a signature" do
      # The `/v4/` generation on `restapi.amap.com`: `/v4/direction/bicycling`,
      # `/v4/grasproad/driving` and `/v4/etd/driving` all answer the Falcon envelope,
      # and none of those pages documents a `sig`.
      host = Host.describe(:restapi, :tsapi)

      assert host.name == :restapi
      assert host.base_url == "https://restapi.amap.com"
      assert host.envelope == :tsapi
      assert host.auth == :key_only
      assert host.key_param == "key"
    end

    test "et-api answers code/msg and names the key clientKey, with digest auth" do
      host = Host.describe(:et_api)

      assert host.base_url == "https://et-api.amap.com"
      assert host.envelope == :code_msg
      assert host.auth == :digest
      assert host.key_param == "clientKey"
    end

    test "apilocate answers status/info/result, plain key, no signature" do
      host = Host.describe(:apilocate)

      assert host.base_url == "https://apilocate.amap.com"
      assert host.envelope == :apilocate
      assert host.auth == :key_only
      assert host.key_param == "key"
    end

    test "names an unknown host, with the ones it knows" do
      error = assert_raise ArgumentError, fn -> Host.describe(:bogus) end

      assert error.message =~ "invalid host: :bogus"
      assert error.message =~ ":restapi"
      assert error.message =~ ":apilocate"
    end

    test "refuses an envelope the host does not answer" do
      error = assert_raise ArgumentError, fn -> Host.describe(:tsapi, :restapi) end

      assert error.message =~ "the :tsapi host"
      assert error.message =~ ":restapi"
    end

    test "refuses an envelope no host answers yet" do
      error = assert_raise ArgumentError, fn -> Host.describe(:restapi, :code_msg) end

      assert error.message =~ "invalid envelope: :code_msg"
    end
  end
end
