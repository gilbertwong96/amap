defmodule Amap.ParamTest do
  use ExUnit.Case, async: true

  alias Amap.Param

  describe "coord/1" do
    test "truncates to 6 decimals" do
      assert Param.coord(116.4810283) == "116.481028"
      assert Param.coord(39.9896431234) == "39.989643"
    end

    test "never uses scientific notation" do
      # Float.to_string/1 would produce "1.0e-5" here, which Amap rejects.
      assert Param.coord(0.00001) == "0.00001"
      assert Param.coord(0.000001) == "0.000001"
      refute Param.coord(0.00001) =~ "e"
    end

    test "accepts integers" do
      assert Param.coord(116) == "116.0"
    end

    test "keeps sign and exact zero" do
      assert Param.coord(-0.000001) == "-0.000001"
      assert Param.coord(0) == "0.0"
    end
  end

  describe "location/1 and locations/1" do
    test "joins longitude and latitude with a comma" do
      assert Param.location({116.481028, 39.989643}) == "116.481028,39.989643"
    end

    test "joins multiple points with a semicolon" do
      assert Param.locations([{116.481028, 39.989643}, {116.434446, 39.90816}]) ==
               "116.481028,39.989643;116.434446,39.90816"
    end
  end

  describe "pipe/1" do
    test "joins with a pipe" do
      assert Param.pipe(["汽车服务", "餐饮服务"]) == "汽车服务|餐饮服务"
    end

    test "passes a single value through" do
      assert Param.pipe(["汽车服务"]) == "汽车服务"
    end
  end

  describe "boolean/2" do
    test "encodes as integers when the endpoint expects 1/0" do
      assert Param.boolean(true, as: :int) == "1"
      assert Param.boolean(false, as: :int) == "0"
    end

    test "encodes as literals when the endpoint expects true/false" do
      assert Param.boolean(true, as: :bool) == "true"
      assert Param.boolean(false, as: :bool) == "false"
    end
  end

  describe "unix_time/1" do
    test "encodes as integer seconds" do
      dt = DateTime.from_unix!(1_700_000_000)
      assert Param.unix_time(dt) == "1700000000"
    end
  end

  describe "props/1" do
    test "encodes a map as a JSON object string" do
      assert Param.props(%{"age" => 30}) == ~s({"age":30})
    end
  end

  describe "encode/1" do
    test "drops nil values instead of sending empty parameters" do
      assert Param.encode(%{"a" => "1", "b" => nil}) == [{"a", "1"}]
    end

    test "stringifies atoms and numbers" do
      assert Param.encode(%{"sid" => 12_345}) == [{"sid", "12345"}]
    end

    test "accepts keyword input" do
      assert Param.encode(a: "1") == [{"a", "1"}]
    end

    test "never encodes a float in scientific notation" do
      # to_string/1 delegates to Float.to_string/1 for floats, which would
      # produce "1.0e-5" and "1.0e21" here — the form Amap rejects.
      assert [{"x", encoded_small}] = Amap.Param.encode(%{"x" => 0.00001})
      assert encoded_small == "0.00001"
      refute encoded_small =~ "e"

      assert [{"x", encoded_large}] = Amap.Param.encode(%{"x" => 1.0e21})
      assert encoded_large == "1000000000000000000000.0"
      refute encoded_large =~ "e"
    end
  end

  describe "lat_lng/1" do
    test "reverses the pair, because the Falcon search endpoints are latitude first" do
      assert Param.lat_lng({116.33, 36.10}) == "36.1,116.33"
      assert Param.lat_lng({114.158, 22.279}) == "22.279,114.158"
    end

    test "rounds to six decimals like coord/1, and never uses scientific notation" do
      assert Param.lat_lng({116.4810283, 39.9896431234}) == "39.989643,116.481028"
      refute Param.lat_lng({0.00001, 0.00001}) =~ "e"
    end
  end

  describe "polygon/1" do
    test "encodes one ring as lat,lon pairs joined by semicolons" do
      ring = [{116.35, 39.98}, {116.36, 39.98}, {116.36, 39.99}]
      assert Param.polygon(ring) == "39.98,116.35;39.98,116.36;39.99,116.36"
    end

    test "encodes several rings separated by a pipe, as the docs describe" do
      ring = [{116.35, 39.98}, {116.36, 39.98}, {116.36, 39.99}]
      other = [{116.40, 39.90}, {116.41, 39.90}, {116.41, 39.91}]

      assert Param.polygon([ring, other]) ==
               "39.98,116.35;39.98,116.36;39.99,116.36|39.9,116.4;39.9,116.41;39.91,116.41"
    end
  end
end
