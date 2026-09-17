defmodule Amap.ParamTest do
  use ExUnit.Case, async: true

  describe "coord/1" do
    test "truncates to 6 decimals" do
      assert Amap.Param.coord(116.4810283) == "116.481028"
      assert Amap.Param.coord(39.9896431234) == "39.989643"
    end

    test "never uses scientific notation" do
      # Float.to_string/1 would produce "1.0e-5" here, which Amap rejects.
      assert Amap.Param.coord(0.00001) == "0.00001"
      assert Amap.Param.coord(0.000001) == "0.000001"
      refute Amap.Param.coord(0.00001) =~ "e"
    end

    test "accepts integers" do
      assert Amap.Param.coord(116) == "116.0"
    end

    test "keeps sign and exact zero" do
      assert Amap.Param.coord(-0.000001) == "-0.000001"
      assert Amap.Param.coord(0) == "0.0"
    end
  end

  describe "location/1 and locations/1" do
    test "joins longitude and latitude with a comma" do
      assert Amap.Param.location({116.481028, 39.989643}) == "116.481028,39.989643"
    end

    test "joins multiple points with a semicolon" do
      assert Amap.Param.locations([{116.481028, 39.989643}, {116.434446, 39.90816}]) ==
               "116.481028,39.989643;116.434446,39.90816"
    end
  end

  describe "pipe/1" do
    test "joins with a pipe" do
      assert Amap.Param.pipe(["汽车服务", "餐饮服务"]) == "汽车服务|餐饮服务"
    end

    test "passes a single value through" do
      assert Amap.Param.pipe(["汽车服务"]) == "汽车服务"
    end
  end

  describe "boolean/2" do
    test "encodes as integers when the endpoint expects 1/0" do
      assert Amap.Param.boolean(true, as: :int) == "1"
      assert Amap.Param.boolean(false, as: :int) == "0"
    end

    test "encodes as literals when the endpoint expects true/false" do
      assert Amap.Param.boolean(true, as: :bool) == "true"
      assert Amap.Param.boolean(false, as: :bool) == "false"
    end
  end

  describe "unix_time/1" do
    test "encodes as integer seconds" do
      dt = DateTime.from_unix!(1_700_000_000)
      assert Amap.Param.unix_time(dt) == "1700000000"
    end
  end

  describe "props/1" do
    test "encodes a map as a JSON object string" do
      assert Amap.Param.props(%{"age" => 30}) == ~s({"age":30})
    end
  end

  describe "encode/1" do
    test "drops nil values instead of sending empty parameters" do
      assert Amap.Param.encode(%{"a" => "1", "b" => nil}) == [{"a", "1"}]
    end

    test "stringifies atoms and numbers" do
      assert Amap.Param.encode(%{"sid" => 12_345}) == [{"sid", "12345"}]
    end

    test "accepts keyword input" do
      assert Amap.Param.encode(a: "1") == [{"a", "1"}]
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
end
