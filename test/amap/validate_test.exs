defmodule Amap.ValidateTest do
  use ExUnit.Case, async: true

  alias Amap.Validate

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

      # An empty string, not nil: `optional!/3` filters nil before a validator
      # sees it, so emptiness is the shape worth pinning here.
      assert_raise ArgumentError, ~r/:desc must be a non-empty string/, fn ->
        Validate.name!("", ":desc")
      end
    end
  end

  describe "text!/2" do
    test "allows an empty string, which an update uses to clear a field" do
      assert Validate.text!("", ":desc") == ""
    end

    test "still applies the character and length rules" do
      assert Validate.text!("货车01", ":name") == "货车01"

      assert_raise ArgumentError, ~r/may not start with an underscore/, fn ->
        Validate.text!("_x", ":desc")
      end

      assert_raise ArgumentError, ~r/may only contain Chinese, letters, digits/, fn ->
        Validate.text!("a b", ":desc")
      end

      assert_raise ArgumentError, ~r/must be at most 128 characters/, fn ->
        Validate.text!(String.duplicate("a", 129), ":desc")
      end
    end
  end

  describe "optional_enum!/3" do
    test "returns the wire string for a documented value" do
      assert Validate.optional_enum!(:base, ":extensions", [:base, :all]) == "base"
      assert Validate.optional_enum!(:all, ":extensions", [:base, :all]) == "all"
    end

    test "treats nil as absent" do
      assert Validate.optional_enum!(nil, ":extensions", [:base, :all]) == nil
    end

    test "raises, naming the allowed values, for anything else" do
      assert_raise ArgumentError,
                   ~r/:extensions must be one of \[:base, :all\], got: :full/,
                   fn -> Validate.optional_enum!(:full, ":extensions", [:base, :all]) end

      assert_raise ArgumentError,
                   ~r/:coordsys must be one of \[:gps\], got: "gps"/,
                   fn -> Validate.optional_enum!("gps", ":coordsys", [:gps]) end
    end
  end

  describe "point!/2 and points!/2" do
    test "accepts pairs of numbers, and a list of them" do
      assert Validate.point!({116.48, 39.99}, ":location") == {116.48, 39.99}
      assert Validate.point!({116, 39}, ":location") == {116, 39}

      assert Validate.points!([{116.48, 39.99}, {114.15, 22.27}], ":locations") ==
               [{116.48, 39.99}, {114.15, 22.27}]
    end

    test "raises for anything Amap would not read as a coordinate" do
      assert_raise ArgumentError,
                   ~r/:location must be a \{lon, lat\} pair of numbers, got: \[116.48, 39.99\]/,
                   fn ->
                     Validate.point!([116.48, 39.99], ":location")
                   end

      assert_raise ArgumentError,
                   ~r/:locations must be a non-empty list of \{lon, lat\} pairs/,
                   fn ->
                     Validate.points!([], ":locations")
                   end

      assert_raise ArgumentError,
                   ~r/:locations must be a \{lon, lat\} pair of numbers, got: "116.48,39.99"/,
                   fn ->
                     Validate.points!(["116.48,39.99"], ":locations")
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
