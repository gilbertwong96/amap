defmodule Amap.Falcon.ValidateTest do
  use ExUnit.Case, async: true

  alias Amap.Falcon.Validate

  describe "name!/2" do
    test "accepts Chinese, letters, digits, underscore and hyphen" do
      assert Validate.name!("货车01", ":name") == "货车01"
      assert Validate.name!("truck_1-a", ":desc") == "truck_1-a"
      assert Validate.name!(String.duplicate("a", 128), ":name") == String.duplicate("a", 128)
    end

    test "raises, naming the field, for every documented rule" do
      assert_raise ArgumentError, ~r/:name must be a non-empty string/, fn ->
        Validate.name!("", ":name")
      end

      assert_raise ArgumentError, ~r/:name may not start with an underscore/, fn ->
        Validate.name!("_x", ":name")
      end

      assert_raise ArgumentError, ~r/:name must be at most 128 characters, got: 129/, fn ->
        Validate.name!(String.duplicate("a", 129), ":name")
      end

      assert_raise ArgumentError, ~r/may only contain Chinese, letters, digits/, fn ->
        Validate.name!("货车 01", ":name")
      end

      assert_raise ArgumentError, ~r/:desc must be a non-empty string/, fn ->
        Validate.name!(nil, ":desc")
      end
    end
  end

  describe "range!/4" do
    test "accepts the documented interval" do
      assert Validate.range!(500, ":radius", 1, 5000) == 500
      assert Validate.range!(1, ":pagesize", 1, 100) == 1
    end

    test "raises outside it" do
      assert_raise ArgumentError, ~r/:radius must be between 1 and 5000, got: 0/, fn ->
        Validate.range!(0, ":radius", 1, 5000)
      end

      assert_raise ArgumentError, ~r/:pagesize must be between 1 and 100, got: 101/, fn ->
        Validate.range!(101, ":pagesize", 1, 100)
      end

      assert_raise ArgumentError, ~r/:radius must be an integer, got: "500"/, fn ->
        Validate.range!("500", ":radius", 1, 5000)
      end
    end
  end

  describe "optional!/3" do
    test "passes a given value to the validator" do
      assert Validate.optional!(&Validate.name!/2, "货车01", ":desc") == "货车01"
    end

    test "treats nil as absent rather than as a value to check" do
      assert Validate.optional!(&Validate.name!/2, nil, ":desc") == nil
    end
  end
end
